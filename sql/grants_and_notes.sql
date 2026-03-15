-- sql/grants_and_notes.sql

/*
  1) DIRECTORY OBJECT
  Run this as a user with CREATE ANY DIRECTORY privilege (typically SYS or SYSTEM).
*/

-- CREATE OR REPLACE DIRECTORY DEVOPS_BACKUP_DIR AS '/path/to/your/os/backup_folder';
-- GRANT READ, WRITE ON DIRECTORY DEVOPS_BACKUP_DIR TO <YOUR_SCHEMA_NAME>;

/*
  2) OS PERMISSIONS
  Ensure the Oracle OS user (usually 'oracle') has read/write permissions 
  on the physical directory '/path/to/your/os/backup_folder'.
*/

/*
  3) APEX PRIVILEGES
  The schema requires access to APEX APIs (APEX_EXPORT, APEX_WEB_SERVICE, APEX_JSON, APEX_CREDENTIAL).
  If using an autonomous database or standard APEX install, these are usually available to the workspace schema.
*/

/*
  4) NETWORK ACL
  To allow the DB to communicate with api.github.com, a Network ACL must be configured.
  Example (run as SYS):
*/
/*
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'api.github.com',
    lower_port => 443,
    upper_port => 443,
    ace => xs$ace_type(privilege_list => xs$name_list('connect', 'resolve'),
                       principal_name => '<YOUR_SCHEMA_NAME>',
                       principal_type => xs_acl.ptype_db)
  );
END;
/
*/
