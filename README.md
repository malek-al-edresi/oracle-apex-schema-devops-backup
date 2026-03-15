# Oracle APEX DevOps Backup System

[![PL/SQL CI](https://github.com/malek-al-edresi/oracle-apex-schema-devops-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/malek-al-edresi/oracle-apex-schema-devops-backup/actions)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Oracle](https://img.shields.io/badge/Oracle-Database_19c%2B-red.svg)](https://www.oracle.com/database/)

A secure, automated solution for full Oracle schema backups, APEX application exports, and direct synchronization to GitHub repositories. This system is designed for enterprise environments requiring centralized logging and robust security.

## Features

- **Full Schema Export**: Automatically extracts DDL for packages, tables, views, triggers, sequences, and more.
- **APEX Integration**: Native export of APEX applications using the `APEX_EXPORT` API.
- **GitHub Sync**: Direct upload to GitHub repositories via REST API.
- **Security First**: No plaintext token storage; utilizes APEX Credentials for sensitive data.
- **Centralized Logging**: Comprehensive tracking of all backup activities with error handling.
- **Transaction Safe**: Library code does not force commits, allowing integration into larger workflows.

## Architecture

The system is built as a modular set of PL/SQL packages:
- `DEVOPS_SEC_SYSTEM_ALL`: Public facade and API entry point.
- `..._SUB_CORE_PKG`: Main orchestrator for the backup workflow.
- `..._SUB_BACKUP_EXPORT_PKG`: Handles DDL extraction to the filesystem.
- `..._SUB_BACKUP_GITHUB_PKG`: Manages GitHub API interactions and uploads.
- `..._SUB_UTILS_PKG`: Secure utility for credential management.

## Security Requirements

> [!IMPORTANT]
> This system is designed to meet security compliance standards by avoiding hardcoded secrets.

1. **APEX Credentials**: Tokens must be stored in the APEX Workspace under "Shared Components > Credentials" with a Static ID (default: `GITHUB_TOKEN_CRED`).
2. **Directory Privileges**: Requires a database directory object with appropriate OS-level permissions for the Oracle user.
3. **Network ACLs**: Access to `api.github.com` must be granted via `DBMS_NETWORK_ACL_ADMIN`.

## Installation

### 1. Database Objects
Run the installation script as the target schema owner:
```sql
@sql/install.sql
```

### 2. Environment Setup (SYSDBA)
Configure the backup directory and network access:
```sql
-- Create directory
CREATE OR REPLACE DIRECTORY DEVOPS_BACKUP_DIR AS '/data/backups/oracle';
GRANT READ, WRITE ON DIRECTORY DEVOPS_BACKUP_DIR TO YOUR_SCHEMA;

-- Enable Network Access
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'api.github.com',
    lower_port => 443,
    upper_port => 443,
    ace => xs$ace_type(privilege_list => xs$name_list('connect', 'resolve'),
                       principal_name => 'YOUR_SCHEMA',
                       principal_type => xs_acl.ptype_db)
  );
END;
/
```

### 3. APEX Configuration
Create a new Credential in your APEX Workspace:
- **Static ID**: `GITHUB_TOKEN_CRED`
- **Username**: (Optional)
- **Password**: Your GitHub Personal Access Token (PAT)

## Usage

### Configure GitHub Settings
Initialize your repository settings:
```sql
BEGIN
  DEVOPS_SEC_SYSTEM_ALL.SET_GITHUB_CONFIG(
    p_repo_owner           => 'your-github-user',
    p_repo_name            => 'your-repo-name',
    p_credential_static_id => 'GITHUB_TOKEN_CRED',
    p_branch               => 'main',
    p_base_path            => 'backups/'
  );
END;
/
```

### Run Backup
Manually trigger a full backup:
```sql
BEGIN
  DEVOPS_SEC_SYSTEM_ALL.RUN_FULL_BACKUP;
END;
/
```

## License
This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---
**Maintained by**: Eng. Malek Mohammed
