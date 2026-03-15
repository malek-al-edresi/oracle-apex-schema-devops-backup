# DEVOPS_SEC_SYSTEM_ALL

Purpose: Full schema backup + APEX export + GitHub upload with centralized logging.

Important security notes:
- Do NOT store GitHub tokens in plaintext. This repository uses APEX credential static IDs or DBMS_CRYPTO encrypted storage. See `install.sql` and `plsql/devops_package_changes.sql`.
- The installation script creates tables/sequences used by packages. Run as the schema owner.
- Remove or adjust directory names and grant UTL_FILE / directory privileges as required by your DBA.

Usage:
1. Run `sqlplus / as sysdba` (or preferred tool) to create directory object and any OS-level folder. Give Oracle read/write to that directory.
2. Run `sqlplus <schema>/<pwd>@<db> @sql/install.sql`
3. Configure GitHub credential: create APEX credential with static id `GITHUB_TOKEN_CRED` (or set the static id you prefer).
4. Call `DEVOPS_SEC_SYSTEM_ALL.SET_GITHUB_CONFIG(...)`
5. Call `DEVOPS_SEC_SYSTEM_ALL.RUN_FULL_BACKUP;`

License: Apache-2.0
