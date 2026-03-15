-- sql/install.sql
-- Run as the schema owner where packages will be compiled.

-- 1) Sequences and tables for config & logging
CREATE SEQUENCE DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG_SEQ START WITH 1 NOCACHE NOCYCLE;
CREATE TABLE DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG (
  config_id   NUMBER PRIMARY KEY,
  repo_owner  VARCHAR2(200),
  repo_name   VARCHAR2(200),
  credential_static_id VARCHAR2(200), -- APEX credential static id or NULL if using encrypted storage
  branch      VARCHAR2(100),
  base_path   VARCHAR2(1000),
  user_by     VARCHAR2(30),
  created_date TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE SEQUENCE DEVOPS_SEC_SYSTEM_ALL_T_BACKUP_LOG_SEQ START WITH 1 NOCACHE NOCYCLE;
CREATE TABLE DEVOPS_SEC_SYSTEM_ALL_T_BACKUP_LOG (
  log_id        NUMBER PRIMARY KEY,
  backup_type   VARCHAR2(200),
  backup_date   TIMESTAMP,
  status        VARCHAR2(50),
  error_message CLOB,
  user_by       VARCHAR2(30)
);

-- 2) Note: create DIRECTORY at DB level and ensure OS dir exists and Oracle has permission
-- Example (run as sysdba):
-- CREATE OR REPLACE DIRECTORY DEVOPS_BACKUP_DIR AS '/data/oracle/devops_backups';
-- GRANT READ, WRITE ON DIRECTORY DEVOPS_BACKUP_DIR TO <your_schema>;

-- 3) APEX credential
-- Create APEX credential via APEX UI or use APEX_INSTANCE_ADMIN APIs:
-- In APEX: Shared Components -> Credentials -> Create Credential static id: GITHUB_TOKEN_CRED
-- The credential should contain username (optional) and password = GitHub personal access token
