// Run a module binary, feed it one fixed record on stdin, capture its stdout. A poll loop writes
// and reads concurrently so a large report (e.g. SAS rows) on stdout cannot deadlock against unread
// stdin. Money and records are marshalled by marshal.hpp; this only moves bytes.
#pragma once

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

namespace lg::proc {

struct result {
  int status;       // child exit code, or -1 if it did not exit normally
  std::string out;  // captured stdout
};

struct spawn_error : std::runtime_error {
  using std::runtime_error::runtime_error;
};

// Run `argv` (argv[0] is the program), write `input` to its stdin, capture up to `max_out` bytes of
// stdout. Throws spawn_error if the child cannot be started or output exceeds max_out.
inline result run(const std::vector<std::string>& argv, const std::string& input,
                  size_t max_out = 8u << 20) {
  if (argv.empty()) throw spawn_error("empty argv");

  int in_pipe[2], out_pipe[2];
  if (pipe(in_pipe) != 0 || pipe(out_pipe) != 0) throw spawn_error("pipe failed");

  pid_t pid = fork();
  if (pid < 0) throw spawn_error("fork failed");

  if (pid == 0) {  // child
    dup2(in_pipe[0], STDIN_FILENO);
    dup2(out_pipe[1], STDOUT_FILENO);
    close(in_pipe[0]); close(in_pipe[1]);
    close(out_pipe[0]); close(out_pipe[1]);
    std::vector<char*> args;
    for (const auto& a : argv) args.push_back(const_cast<char*>(a.c_str()));
    args.push_back(nullptr);
    execvp(args[0], args.data());
    _exit(127);  // exec failed
  }

  // parent
  close(in_pipe[0]);
  close(out_pipe[1]);
  ::signal(SIGPIPE, SIG_IGN);
  fcntl(in_pipe[1], F_SETFL, O_NONBLOCK);
  fcntl(out_pipe[0], F_SETFL, O_NONBLOCK);

  std::string out;
  size_t written = 0;
  bool writing = true, reading = true;
  if (input.empty()) { close(in_pipe[1]); writing = false; }

  char buf[65536];
  while (reading) {
    struct pollfd fds[2];
    int n = 0;
    int read_idx = -1, write_idx = -1;
    if (reading) { fds[n] = {out_pipe[0], POLLIN, 0}; read_idx = n++; }
    if (writing) { fds[n] = {in_pipe[1], POLLOUT, 0}; write_idx = n++; }
    if (poll(fds, n, -1) < 0) { if (errno == EINTR) continue; break; }

    if (write_idx >= 0 && (fds[write_idx].revents & (POLLOUT | POLLERR | POLLHUP))) {
      ssize_t w = write(in_pipe[1], input.data() + written, input.size() - written);
      if (w > 0) written += static_cast<size_t>(w);
      if (w < 0 && errno != EAGAIN && errno != EINTR) { writing = false; close(in_pipe[1]); }
      if (writing && written == input.size()) { writing = false; close(in_pipe[1]); }
    }
    if (read_idx >= 0 && (fds[read_idx].revents & (POLLIN | POLLERR | POLLHUP))) {
      ssize_t r = read(out_pipe[0], buf, sizeof(buf));
      if (r > 0) {
        if (out.size() + static_cast<size_t>(r) > max_out) {
          close(out_pipe[0]); if (writing) close(in_pipe[1]);
          waitpid(pid, nullptr, 0);
          throw spawn_error("child stdout exceeded max_out");
        }
        out.append(buf, static_cast<size_t>(r));
      } else if (r == 0) {
        reading = false;
      } else if (errno != EAGAIN && errno != EINTR) {
        reading = false;
      }
    }
  }

  close(out_pipe[0]);
  if (writing) close(in_pipe[1]);
  int wstatus = 0;
  waitpid(pid, &wstatus, 0);
  return {WIFEXITED(wstatus) ? WEXITSTATUS(wstatus) : -1, out};
}

}  // namespace lg::proc
