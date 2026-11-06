       IDENTIFICATION DIVISION.
       PROGRAM-ID. LOADVSAM.
      *> Loads the pipe-delimited account seed into the VSAM/ISAM account master (GnuCOBOL INDEXED
      *> over Berkeley DB). Paths from env SEED_FILE and ACCT_FILE. Pure file IO (no EXEC SQL).
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT SEED-FILE ASSIGN TO WS-SEED-PATH
               ORGANIZATION LINE SEQUENTIAL
               FILE STATUS WS-SEED-ST.
           SELECT ACCT-FILE ASSIGN TO WS-ACCT-PATH
               ORGANIZATION INDEXED ACCESS DYNAMIC
               RECORD KEY AM-ACCOUNT-ID
               FILE STATUS WS-ACCT-ST.
       DATA DIVISION.
       FILE SECTION.
       FD  SEED-FILE.
       01  SEED-LINE            PIC X(200).
       FD  ACCT-FILE.
           COPY "account-master.cpy".
       WORKING-STORAGE SECTION.
           01 WS-SEED-PATH      PIC X(80).
           01 WS-ACCT-PATH      PIC X(80).
           01 WS-SEED-ST        PIC X(02).
           01 WS-ACCT-ST        PIC X(02).
           01 WS-BAL-TEXT       PIC X(20).
           01 WS-EOF            PIC X(01) VALUE "N".
           01 WS-COUNT          PIC 9(05) VALUE 0.
       PROCEDURE DIVISION.
       MAIN-PARA.
           DISPLAY "SEED_FILE" UPON ENVIRONMENT-NAME.
           ACCEPT WS-SEED-PATH FROM ENVIRONMENT-VALUE.
           DISPLAY "ACCT_FILE" UPON ENVIRONMENT-NAME.
           ACCEPT WS-ACCT-PATH FROM ENVIRONMENT-VALUE.
           OPEN INPUT SEED-FILE.
           OPEN OUTPUT ACCT-FILE.
           PERFORM UNTIL WS-EOF = "Y"
              READ SEED-FILE
                 AT END MOVE "Y" TO WS-EOF
                 NOT AT END PERFORM LOAD-ONE
              END-READ
           END-PERFORM.
           CLOSE SEED-FILE.
           CLOSE ACCT-FILE.
           DISPLAY "LOADED=" WS-COUNT.
           PERFORM VERIFY-ONE.
           STOP RUN.
       LOAD-ONE.
           MOVE SPACES TO ACCOUNT-MASTER-RECORD.
           UNSTRING SEED-LINE DELIMITED BY "|"
              INTO AM-ACCOUNT-ID AM-CUSTOMER-ID AM-BRANCH
                   AM-ACCOUNT-TYPE AM-CURRENCY WS-BAL-TEXT
                   AM-STATUS AM-OPENED-AT
           END-UNSTRING.
           MOVE FUNCTION NUMVAL(WS-BAL-TEXT) TO AM-BALANCE.
           WRITE ACCOUNT-MASTER-RECORD.
           ADD 1 TO WS-COUNT.
       VERIFY-ONE.
           OPEN INPUT ACCT-FILE.
           MOVE "000000000042" TO AM-ACCOUNT-ID.
           READ ACCT-FILE
              KEY IS AM-ACCOUNT-ID
              INVALID KEY DISPLAY "VERIFY: NOT FOUND"
              NOT INVALID KEY
                 DISPLAY "VERIFY 042 BAL=" AM-BALANCE
                 DISPLAY "  STATUS=" AM-STATUS " BRANCH=" AM-BRANCH
           END-READ.
           CLOSE ACCT-FILE.
