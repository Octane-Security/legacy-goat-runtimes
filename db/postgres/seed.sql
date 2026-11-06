-- Staff seed. pw_hash = sha256(salt || password), salt 'SALT' space-padded to 16 bytes (PIC X(16)),
-- as LGHASH computes it. Lab passwords: TLR001=teller-pw SUP001=super-pw TLR014=teller14-pw.
INSERT INTO staff (staff_id, name, role, branch, pw_hash, status) VALUES
  ('TLR001','Terry Teller','TELLER','0007','18b7317b9d4eafa77156a0c3d65df4afd4afb5a2d31b7d1c0244a7433f0d6170','ACTIVE'),
  ('SUP001','Sam Supervisor','SUPERVISOR','0007','9142a3d2c8c40881c011c8a0b223a5d6d82001b353e10fe8e2be4eaa58e1a477','ACTIVE'),
  ('TLR014','Tina Teller','TELLER','0014','b37b9a859368de3debba5edf87bd86f816885bc608208ec698d1b6c79a469331','ACTIVE')
ON CONFLICT (staff_id) DO NOTHING;
