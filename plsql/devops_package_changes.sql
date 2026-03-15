-- plsql/devops_package_changes.sql
-- Purpose: Complete, secure PL/SQL package implementations for Oracle APEX DevOps Backup.
-- This file contains all required packages and bodies with security enhancements applied.

SET DEFINE OFF;

----------------------------------------------------------------------
-- 1) UTILS PACKAGE (Secure Credential Handling)
----------------------------------------------------------------------
CREATE OR REPLACE PACKAGE DEVOPS_SEC_SYSTEM_ALL_SUB_UTILS_PKG AS
  -- Retrieve token from APEX Credentials.
  FUNCTION get_github_token(p_static_id IN VARCHAR2 DEFAULT 'GITHUB_TOKEN_CRED') RETURN VARCHAR2;
END DEVOPS_SEC_SYSTEM_ALL_SUB_UTILS_PKG;
/

CREATE OR REPLACE PACKAGE BODY DEVOPS_SEC_SYSTEM_ALL_SUB_UTILS_PKG AS
  FUNCTION get_github_token(p_static_id IN VARCHAR2 DEFAULT 'GITHUB_TOKEN_CRED') RETURN VARCHAR2 IS
    l_username VARCHAR2(4000);
    l_password VARCHAR2(4000);
  BEGIN
    APEX_CREDENTIAL.GET_CREDENTIAL(
      p_static_id => p_static_id,
      p_username  => l_username,
      p_password  => l_password
    );

    IF l_password IS NULL THEN
      RAISE_APPLICATION_ERROR(-20002, 'GitHub token credential "' || p_static_id || '" not found or empty.');
    END IF;

    RETURN l_password;
  EXCEPTION
    WHEN OTHERS THEN
      -- Centralized logging if available, otherwise re-raise
      RAISE;
  END get_github_token;
END;
/

----------------------------------------------------------------------
-- 2) LOGGING PACKAGE (Centralized tracking)
----------------------------------------------------------------------
CREATE OR REPLACE PACKAGE DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG AS
    PROCEDURE log_backup(
        p_backup_type   IN VARCHAR2,
        p_status        IN VARCHAR2,
        p_error_message IN VARCHAR2 DEFAULT NULL
    );
     
    PROCEDURE log_error_and_raise(
        p_source_procedure IN VARCHAR2,
        p_custom_message   IN VARCHAR2,
        p_stop_apex_engine IN BOOLEAN DEFAULT TRUE
    );
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG;
/

CREATE OR REPLACE PACKAGE BODY DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG AS
    PROCEDURE log_error_and_raise(
        p_source_procedure IN VARCHAR2,
        p_custom_message   IN VARCHAR2,
        p_stop_apex_engine IN BOOLEAN DEFAULT TRUE
    ) IS
    BEGIN
        log_backup(p_source_procedure, 'ERROR', p_custom_message);
        -- Note: APP_BASE_PKG dependency assumes it exists in target environment.
        -- If not, replace with standard RAISE_APPLICATION_ERROR.
        BEGIN
          EXECUTE IMMEDIATE 'BEGIN APP_BASE_PKG.log_error_and_raise(:1, :2, :3, :4); END;' 
          USING 'DEVOPS', p_source_procedure, NVL(p_custom_message, '') || ' - ' || SQLERRM, p_stop_apex_engine;
        EXCEPTION WHEN OTHERS THEN
          RAISE_APPLICATION_ERROR(-20001, p_source_procedure || ': ' || p_custom_message || ' - ' || SQLERRM);
        END;
    END log_error_and_raise;
     
    PROCEDURE log_backup(
        p_backup_type   IN VARCHAR2,
        p_status        IN VARCHAR2,
        p_error_message IN VARCHAR2 DEFAULT NULL
    ) IS
      PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO DEVOPS_SEC_SYSTEM_ALL_T_BACKUP_LOG (
            log_id, backup_type, backup_date, status, error_message, user_by
        ) VALUES (
            DEVOPS_SEC_SYSTEM_ALL_T_BACKUP_LOG_SEQ.NEXTVAL,
            p_backup_type, SYSTIMESTAMP, p_status, p_error_message, USER
        );
        COMMIT; 
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            -- Do not raise from log function to avoid stopping main process if logging fails
    END log_backup;
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG;
/

----------------------------------------------------------------------
-- 3) EXPORT PACKAGE (Schema to SQL extraction)
----------------------------------------------------------------------
CREATE OR REPLACE PACKAGE DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG AS 
    c_directory CONSTANT VARCHAR2(30) := 'DEVOPS_BACKUP_DIR'; 

    PROCEDURE write_clob_to_file(p_file IN UTL_FILE.FILE_TYPE, p_clob IN CLOB); 
    PROCEDURE backup_all_packages; 
    PROCEDURE backup_all_procedures; 
    PROCEDURE backup_all_functions; 
    PROCEDURE backup_all_views; 
    PROCEDURE backup_all_triggers; 
    PROCEDURE backup_all_tables; 
    PROCEDURE backup_all_sequences; 
    PROCEDURE backup_all_indexes; 
    PROCEDURE backup_all_constraints; 
    PROCEDURE backup_all_grants; 
    PROCEDURE backup_all_synonyms; 
    PROCEDURE backup_all_types; 
    PROCEDURE backup_all_mat_views; 
    PROCEDURE backup_all_scheduler_jobs; 
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG;
/

CREATE OR REPLACE PACKAGE BODY DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG AS   
    PROCEDURE write_clob_to_file(p_file IN UTL_FILE.FILE_TYPE, p_clob IN CLOB) IS 
        v_offset     PLS_INTEGER := 1; 
        v_chunk      PLS_INTEGER := 32767; 
        v_buffer     VARCHAR2(32767); 
        v_clob_len   INTEGER; 
        v_read_len   PLS_INTEGER; 
    BEGIN 
        IF p_clob IS NULL THEN RETURN; END IF; 
        v_clob_len := DBMS_LOB.GETLENGTH(p_clob); 
        WHILE v_offset <= v_clob_len LOOP 
            v_read_len := LEAST(v_chunk, v_clob_len - v_offset + 1); 
            DBMS_LOB.READ(p_clob, v_read_len, v_offset, v_buffer); 
            UTL_FILE.PUT(p_file, v_buffer); 
            v_offset := v_offset + v_chunk; 
        END LOOP; 
    EXCEPTION WHEN OTHERS THEN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('WRITE_CLOB_TO_FILE', 'FAILED', SQLERRM); 
    END write_clob_to_file; 

    PROCEDURE backup_all_packages IS 
        v_file   UTL_FILE.FILE_TYPE; 
        v_ddl    CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_packages.sql', 'w', 32767); 
        UTL_FILE.PUT_LINE(v_file, '-- Backup packages on ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS')); 
        FOR rec IN (SELECT DISTINCT OBJECT_NAME FROM USER_OBJECTS WHERE OBJECT_TYPE IN ('PACKAGE', 'PACKAGE BODY') ORDER BY OBJECT_NAME) LOOP 
            BEGIN 
                v_ddl := DBMS_METADATA.GET_DDL('PACKAGE', rec.OBJECT_NAME); 
                UTL_FILE.PUT_LINE(v_file, 'PROMPT ===== PACKAGE SPEC: ' || rec.OBJECT_NAME); 
                write_clob_to_file(v_file, v_ddl); 
                UTL_FILE.PUT_LINE(v_file, '/'); 
            EXCEPTION WHEN OTHERS THEN NULL; END; 
            BEGIN 
                v_ddl := DBMS_METADATA.GET_DDL('PACKAGE_BODY', rec.OBJECT_NAME); 
                UTL_FILE.PUT_LINE(v_file, 'PROMPT ===== PACKAGE BODY: ' || rec.OBJECT_NAME); 
                write_clob_to_file(v_file, v_ddl); 
                UTL_FILE.PUT_LINE(v_file, '/'); 
            EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('PACKAGES', 'SUCCESS', NULL); 
    EXCEPTION WHEN OTHERS THEN 
        IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('PACKAGES', 'FAILED', SQLERRM); 
    END backup_all_packages; 

    -- Other procedures implemented following same pattern
    PROCEDURE backup_all_procedures IS 
        v_file   UTL_FILE.FILE_TYPE; 
        v_ddl    CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_procedures.sql', 'w', 32767); 
        UTL_FILE.PUT_LINE(v_file, 'SET DEFINE OFF;'); 
        FOR rec IN (SELECT OBJECT_NAME FROM USER_OBJECTS WHERE OBJECT_TYPE = 'PROCEDURE' ORDER BY OBJECT_NAME) LOOP 
            BEGIN 
                v_ddl := DBMS_METADATA.GET_DDL('PROCEDURE', rec.OBJECT_NAME); 
                UTL_FILE.PUT_LINE(v_file, 'PROMPT ===== PROCEDURE: ' || rec.OBJECT_NAME); 
                write_clob_to_file(v_file, v_ddl); 
                UTL_FILE.PUT_LINE(v_file, '/'); 
            EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('PROCEDURES', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN 
        IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('PROCEDURES', 'FAILED', SQLERRM); 
    END backup_all_procedures;

    PROCEDURE backup_all_functions IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_functions.sql', 'w', 32767); 
        UTL_FILE.PUT_LINE(v_file, 'SET DEFINE OFF;'); 
        FOR rec IN (SELECT OBJECT_NAME FROM USER_OBJECTS WHERE OBJECT_TYPE = 'FUNCTION' ORDER BY OBJECT_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('FUNCTION', rec.OBJECT_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('FUNCTIONS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('FUNCTIONS', 'FAILED', SQLERRM); 
    END backup_all_functions;

    PROCEDURE backup_all_views IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_views.sql', 'w', 32767); 
        FOR rec IN (SELECT OBJECT_NAME FROM USER_OBJECTS WHERE OBJECT_TYPE = 'VIEW' ORDER BY OBJECT_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('VIEW', rec.OBJECT_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('VIEWS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('VIEWS', 'FAILED', SQLERRM); 
    END backup_all_views;

    PROCEDURE backup_all_triggers IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_triggers.sql', 'w', 32767); 
        FOR rec IN (SELECT OBJECT_NAME FROM USER_OBJECTS WHERE OBJECT_TYPE = 'TRIGGER' ORDER BY OBJECT_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('TRIGGER', rec.OBJECT_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('TRIGGERS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('TRIGGERS', 'FAILED', SQLERRM); 
    END backup_all_triggers;

    PROCEDURE backup_all_tables IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_tables.sql', 'w', 32767); 
        FOR rec IN (SELECT TABLE_NAME FROM USER_TABLES ORDER BY TABLE_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('TABLE', rec.TABLE_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('TABLES', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('TABLES', 'FAILED', SQLERRM); 
    END backup_all_tables;

    PROCEDURE backup_all_sequences IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_sequences.sql', 'w', 32767); 
        FOR rec IN (SELECT SEQUENCE_NAME FROM USER_SEQUENCES ORDER BY SEQUENCE_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('SEQUENCE', rec.SEQUENCE_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('SEQUENCES', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('SEQUENCES', 'FAILED', SQLERRM); 
    END backup_all_sequences;

    PROCEDURE backup_all_indexes IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_indexes.sql', 'w', 32767); 
        FOR rec IN (SELECT INDEX_NAME FROM USER_INDEXES WHERE INDEX_TYPE != 'LOB' ORDER BY INDEX_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('INDEX', rec.INDEX_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('INDEXES', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('INDEXES', 'FAILED', SQLERRM); 
    END backup_all_indexes;

    PROCEDURE backup_all_constraints IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_constraints.sql', 'w', 32767); 
        FOR rec IN (SELECT DISTINCT TABLE_NAME FROM USER_CONSTRAINTS WHERE CONSTRAINT_TYPE IN ('P', 'R', 'U', 'C') ORDER BY TABLE_NAME) LOOP 
            BEGIN 
                v_ddl := DBMS_METADATA.GET_DEPENDENT_DDL('CONSTRAINT', rec.TABLE_NAME); 
                write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); 
                v_ddl := DBMS_METADATA.GET_DEPENDENT_DDL('REF_CONSTRAINT', rec.TABLE_NAME); 
                write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); 
            EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('CONSTRAINTS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('CONSTRAINTS', 'FAILED', SQLERRM); 
    END backup_all_constraints;

    PROCEDURE backup_all_grants IS 
        v_file UTL_FILE.FILE_TYPE; v_sql VARCHAR2(4000); 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_grants.sql', 'w', 32767); 
        FOR rec IN (SELECT PRIVILEGE, TABLE_NAME, GRANTEE FROM USER_TAB_PRIVS ORDER BY GRANTEE, TABLE_NAME) LOOP 
            v_sql := 'GRANT ' || rec.PRIVILEGE || ' ON ' || rec.TABLE_NAME || ' TO ' || rec.GRANTEE || ';'; UTL_FILE.PUT_LINE(v_file, v_sql); 
        END LOOP; 
        FOR r IN (SELECT GRANTED_ROLE, USERNAME FROM USER_ROLE_PRIVS ORDER BY USERNAME) LOOP 
            v_sql := 'GRANT ' || r.GRANTED_ROLE || ' TO ' || r.USERNAME || ';'; UTL_FILE.PUT_LINE(v_file, v_sql); 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('GRANTS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('GRANTS', 'FAILED', SQLERRM); 
    END backup_all_grants;

    PROCEDURE backup_all_synonyms IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_synonyms.sql', 'w', 32767); 
        FOR rec IN (SELECT SYNONYM_NAME FROM USER_SYNONYMS ORDER BY SYNONYM_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('SYNONYM', rec.SYNONYM_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('SYNONYMS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('SYNONYMS', 'FAILED', SQLERRM); 
    END backup_all_synonyms;

    PROCEDURE backup_all_types IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_types.sql', 'w', 32767); 
        FOR rec IN (SELECT OBJECT_NAME FROM USER_OBJECTS WHERE OBJECT_TYPE = 'TYPE' ORDER BY OBJECT_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('TYPE', rec.OBJECT_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('TYPES', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('TYPES', 'FAILED', SQLERRM); 
    END backup_all_types;

    PROCEDURE backup_all_mat_views IS 
        v_file UTL_FILE.FILE_TYPE; v_ddl CLOB; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_mat_views.sql', 'w', 32767); 
        FOR rec IN (SELECT MVIEW_NAME FROM USER_MVIEWS ORDER BY MVIEW_NAME) LOOP 
            BEGIN v_ddl := DBMS_METADATA.GET_DDL('MATERIALIZED_VIEW', rec.MVIEW_NAME); write_clob_to_file(v_file, v_ddl); UTL_FILE.PUT_LINE(v_file, '/'); EXCEPTION WHEN OTHERS THEN NULL; END; 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('MAT_VIEWS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('MAT_VIEWS', 'FAILED', SQLERRM); 
    END backup_all_mat_views;

    PROCEDURE backup_all_scheduler_jobs IS 
        v_file UTL_FILE.FILE_TYPE; 
    BEGIN 
        v_file := UTL_FILE.FOPEN(c_directory, 'backup_scheduler_jobs.sql', 'w', 32767); 
        FOR rec IN (SELECT JOB_NAME, JOB_ACTION, REPEAT_INTERVAL, ENABLED FROM USER_SCHEDULER_JOBS ORDER BY JOB_NAME) LOOP 
            UTL_FILE.PUT_LINE(v_file, 'BEGIN DBMS_SCHEDULER.CREATE_JOB(job_name=>''' || rec.JOB_NAME || ''', job_type=>''PLSQL_BLOCK'', job_action=>q''[' || rec.JOB_ACTION || ']'', repeat_interval=>''' || rec.REPEAT_INTERVAL || ''', enabled=>' || rec.ENABLED || '); END;'); 
            UTL_FILE.PUT_LINE(v_file, '/'); 
        END LOOP; 
        UTL_FILE.FCLOSE(v_file); DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('SCHEDULER_JOBS', 'SUCCESS'); 
    EXCEPTION WHEN OTHERS THEN IF UTL_FILE.IS_OPEN(v_file) THEN UTL_FILE.FCLOSE(v_file); END IF; DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('SCHEDULER_JOBS', 'FAILED', SQLERRM); 
    END backup_all_scheduler_jobs; 
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG;
/

----------------------------------------------------------------------
-- 4) GITHUB PACKAGE (Secure API interaction)
----------------------------------------------------------------------
CREATE OR REPLACE PACKAGE DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_GITHUB_PKG AS 
    PROCEDURE SET_GITHUB_CONFIG( 
        p_repo_owner    IN VARCHAR2, 
        p_repo_name     IN VARCHAR2, 
        p_credential_static_id IN VARCHAR2 DEFAULT 'GITHUB_TOKEN_CRED', 
        p_branch        IN VARCHAR2 DEFAULT 'main', 
        p_base_path     IN VARCHAR2 DEFAULT '' 
    ); 

    FUNCTION read_file_to_clob(p_file_name IN VARCHAR2) RETURN CLOB; 
    FUNCTION clob_to_blob(p_clob IN CLOB) RETURN BLOB; 
    FUNCTION blob_to_base64_clob(p_blob IN BLOB) RETURN CLOB; 

    FUNCTION github_get_sha( 
        p_repo_owner IN VARCHAR2, 
        p_repo_name  IN VARCHAR2, 
        p_path       IN VARCHAR2, 
        p_branch     IN VARCHAR2, 
        p_token      IN VARCHAR2 
    ) RETURN VARCHAR2; 

    PROCEDURE upload_clob_file_to_github( 
        p_file_name  IN VARCHAR2, 
        p_repo_owner IN VARCHAR2, 
        p_repo_name  IN VARCHAR2, 
        p_branch     IN VARCHAR2, 
        p_base_path  IN VARCHAR2, 
        p_token      IN VARCHAR2 
    ); 

    PROCEDURE UPLOAD_ALL_BACKUPS; 
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_GITHUB_PKG;
/

CREATE OR REPLACE PACKAGE BODY DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_GITHUB_PKG AS 
    PROCEDURE SET_GITHUB_CONFIG( 
        p_repo_owner    IN VARCHAR2, 
        p_repo_name     IN VARCHAR2, 
        p_credential_static_id IN VARCHAR2 DEFAULT 'GITHUB_TOKEN_CRED', 
        p_branch        IN VARCHAR2 DEFAULT 'main', 
        p_base_path     IN VARCHAR2 DEFAULT '' 
    ) IS 
    BEGIN 
        DELETE FROM DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG; 
        INSERT INTO DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG ( 
            config_id, repo_owner, repo_name, credential_static_id, branch, base_path, user_by, created_date 
        ) VALUES ( 
            DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG_SEQ.NEXTVAL, 
            p_repo_owner, p_repo_name, p_credential_static_id, p_branch, p_base_path, USER, SYSTIMESTAMP 
        ); 
        -- COMMIT intentionally omitted; caller controls transaction.
    EXCEPTION WHEN OTHERS THEN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_error_and_raise('SET_GITHUB_CONFIG', 'Failed to set GitHub config: ' || SQLERRM); 
    END SET_GITHUB_CONFIG; 
     
    FUNCTION read_file_to_clob(p_file_name IN VARCHAR2) RETURN CLOB IS 
        v_bfile BFILE; v_clob CLOB; 
        v_dest_offset INTEGER := 1; v_src_offset INTEGER := 1; 
        v_lang_context INTEGER := DBMS_LOB.DEFAULT_LANG_CTX; v_warning INTEGER; 
    BEGIN 
        v_bfile := BFILENAME(DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.c_directory, p_file_name); 
        IF DBMS_LOB.FILEEXISTS(v_bfile) = 0 THEN RETURN NULL; END IF; 
        DBMS_LOB.FILEOPEN(v_bfile, DBMS_LOB.FILE_READONLY); 
        DBMS_LOB.CREATETEMPORARY(v_clob, TRUE); 
        DBMS_LOB.LOADCLOBFROMFILE(v_clob, v_bfile, DBMS_LOB.LOBMAXSIZE, v_dest_offset, v_src_offset, DBMS_LOB.DEFAULT_CSID, v_lang_context, v_warning); 
        DBMS_LOB.FILECLOSE(v_bfile); 
        RETURN v_clob; 
    EXCEPTION WHEN OTHERS THEN 
        IF DBMS_LOB.FILEISOPEN(v_bfile) = 1 THEN DBMS_LOB.FILECLOSE(v_bfile); END IF; 
        RETURN NULL; 
    END read_file_to_clob; 
     
    FUNCTION clob_to_blob(p_clob IN CLOB) RETURN BLOB IS 
        v_blob BLOB; 
        v_dest_offset INTEGER := 1; v_src_offset INTEGER := 1; 
        v_lang_context INTEGER := DBMS_LOB.DEFAULT_LANG_CTX; v_warning INTEGER; 
    BEGIN 
        DBMS_LOB.CREATETEMPORARY(v_blob, TRUE); 
        IF p_clob IS NOT NULL THEN 
            DBMS_LOB.CONVERTTOBLOB(v_blob, p_clob, DBMS_LOB.LOBMAXSIZE, v_dest_offset, v_src_offset, DBMS_LOB.DEFAULT_CSID, v_lang_context, v_warning); 
        END IF; 
        RETURN v_blob; 
    EXCEPTION WHEN OTHERS THEN 
        IF DBMS_LOB.ISTEMPORARY(v_blob) = 1 THEN DBMS_LOB.FREETEMPORARY(v_blob); END IF; RAISE; 
    END clob_to_blob; 
     
    FUNCTION blob_to_base64_clob(p_blob IN BLOB) RETURN CLOB IS 
        v_out CLOB; v_pos INTEGER := 1; v_len INTEGER; v_raw RAW(24576); v_read_len INTEGER; 
        v_chunk INTEGER := 17997; v_piece VARCHAR2(32767); 
    BEGIN 
        IF p_blob IS NULL THEN RETURN NULL; END IF; 
        DBMS_LOB.CREATETEMPORARY(v_out, TRUE); v_len := DBMS_LOB.GETLENGTH(p_blob); 
        WHILE v_pos <= v_len LOOP 
            v_read_len := LEAST(v_chunk, v_len - v_pos + 1); 
            DBMS_LOB.READ(p_blob, v_read_len, v_pos, v_raw); 
            v_piece := UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(v_raw)); 
            v_piece := REPLACE(REPLACE(v_piece, CHR(10), ''), CHR(13), ''); 
            DBMS_LOB.WRITEAPPEND(v_out, LENGTH(v_piece), v_piece); 
            v_pos := v_pos + v_chunk; 
        END LOOP; 
        RETURN v_out; 
    EXCEPTION WHEN OTHERS THEN 
        IF DBMS_LOB.ISTEMPORARY(v_out) = 1 THEN DBMS_LOB.FREETEMPORARY(v_out); END IF; RAISE; 
    END blob_to_base64_clob; 
     
    FUNCTION github_get_sha(p_repo_owner IN VARCHAR2, p_repo_name IN VARCHAR2, p_path IN VARCHAR2, p_branch IN VARCHAR2, p_token IN VARCHAR2) RETURN VARCHAR2 IS 
        l_resp CLOB; 
    BEGIN 
        apex_web_service.clear_request_headers; 
        apex_web_service.set_request_headers( 
            p_name_01 => 'Authorization', p_value_01 => 'token ' || p_token, 
            p_name_02 => 'User-Agent',    p_value_02 => 'Oracle-APEX', 
            p_name_03 => 'Accept',        p_value_03 => 'application/vnd.github.v3+json' 
        ); 
        l_resp := apex_web_service.make_rest_request( 
            p_url => 'https://api.github.com/repos/' || p_repo_owner || '/' || p_repo_name || '/contents/' || p_path || '?ref=' || p_branch, 
            p_http_method => 'GET', p_transfer_timeout => 100 
        ); 
        RETURN json_value(l_resp, '$.sha'); 
    EXCEPTION WHEN OTHERS THEN RETURN NULL; 
    END github_get_sha; 
     
    PROCEDURE upload_clob_file_to_github(p_file_name IN VARCHAR2, p_repo_owner IN VARCHAR2, p_repo_name IN VARCHAR2, p_branch IN VARCHAR2, p_base_path IN VARCHAR2, p_token IN VARCHAR2) IS 
        l_clob CLOB; l_blob BLOB; l_b64_clob CLOB; l_json CLOB; l_resp CLOB; l_sha VARCHAR2(200); l_path VARCHAR2(1000); 
    BEGIN 
        l_clob := read_file_to_clob(p_file_name); 
        IF l_clob IS NULL THEN RETURN; END IF; 
        l_blob := clob_to_blob(l_clob); 
        l_b64_clob := blob_to_base64_clob(l_blob); 
        l_path := CASE WHEN p_base_path IS NULL THEN p_file_name ELSE RTRIM(LTRIM(p_base_path, '/'), '/') || '/' || p_file_name END; 
        l_sha := github_get_sha(p_repo_owner, p_repo_name, l_path, p_branch, p_token); 
        apex_json.initialize_clob_output; 
        apex_json.open_object; 
        apex_json.write('message', 'Upload ' || p_file_name); 
        apex_json.write('content', l_b64_clob); 
        IF l_sha IS NOT NULL THEN apex_json.write('sha', l_sha); END IF; 
        apex_json.write('branch', p_branch); 
        apex_json.close_object; 
        l_json := apex_json.get_clob_output; apex_json.free_output; 
        apex_web_service.clear_request_headers; 
        apex_web_service.set_request_headers(p_name_01 => 'Authorization', p_value_01 => 'token ' || p_token, p_name_02 => 'User-Agent', p_value_02 => 'Oracle-APEX', p_name_03 => 'Content-Type', p_value_03 => 'application/json'); 
        l_resp := apex_web_service.make_rest_request(p_url => 'https://api.github.com/repos/' || p_repo_owner || '/' || p_repo_name || '/contents/' || l_path, p_http_method => 'PUT', p_body => l_json, p_transfer_timeout => 120); 
        IF apex_web_service.g_status_code NOT IN (200, 201) THEN 
            RAISE_APPLICATION_ERROR(-20001, 'GitHub upload failed: ' || p_file_name || ' Status=' || apex_web_service.g_status_code); 
        END IF; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('GITHUB_UPLOAD', 'SUCCESS', 'Uploaded: ' || p_file_name); 
    EXCEPTION WHEN OTHERS THEN 
        IF DBMS_LOB.ISTEMPORARY(l_json) = 1 THEN DBMS_LOB.FREETEMPORARY(l_json); END IF; 
        IF DBMS_LOB.ISTEMPORARY(l_b64_clob) = 1 THEN DBMS_LOB.FREETEMPORARY(l_b64_clob); END IF; 
        IF DBMS_LOB.ISTEMPORARY(l_blob) = 1 THEN DBMS_LOB.FREETEMPORARY(l_blob); END IF; 
        IF DBMS_LOB.ISTEMPORARY(l_clob) = 1 THEN DBMS_LOB.FREETEMPORARY(l_clob); END IF; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_error_and_raise('UPLOAD_CLOB_FILE_TO_GITHUB', 'Failed on file ' || p_file_name || ': ' || SQLERRM); 
    END upload_clob_file_to_github; 
     
    PROCEDURE UPLOAD_ALL_BACKUPS IS 
        CURSOR backup_files_cur IS 
            SELECT column_value AS filename FROM TABLE(sys.odcivarchar2list('backup_packages.sql','backup_procedures.sql','backup_functions.sql','backup_views.sql','backup_triggers.sql','backup_tables.sql','backup_sequences.sql','backup_indexes.sql','backup_constraints.sql','backup_grants.sql','backup_synonyms.sql','backup_types.sql','backup_mat_views.sql','backup_scheduler_jobs.sql'));
        l_config_rec DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG%ROWTYPE; l_token VARCHAR2(4000); 
    BEGIN 
        SELECT config_id, repo_owner, repo_name, credential_static_id, branch, base_path 
        INTO l_config_rec.config_id, l_config_rec.repo_owner, l_config_rec.repo_name, l_config_rec.credential_static_id, l_config_rec.branch, l_config_rec.base_path 
        FROM DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG 
        WHERE config_id = (SELECT MAX(config_id) FROM DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG); 
        l_token := DEVOPS_SEC_SYSTEM_ALL_SUB_UTILS_PKG.get_github_token(NVL(l_config_rec.credential_static_id, 'GITHUB_TOKEN_CRED')); 
        FOR f IN backup_files_cur LOOP 
            BEGIN 
                upload_clob_file_to_github(p_file_name => f.filename, p_repo_owner => l_config_rec.repo_owner, p_repo_name => l_config_rec.repo_name, p_branch => NVL(l_config_rec.branch, 'main'), p_base_path => NVL(l_config_rec.base_path, '') || 'schema/', p_token => l_token); 
            EXCEPTION WHEN OTHERS THEN 
                DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('GITHUB_UPLOAD', 'FAILED', 'File ' || f.filename || ': ' || SQLERRM); 
            END; 
        END LOOP; 
    EXCEPTION 
        WHEN NO_DATA_FOUND THEN DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('GITHUB_UPLOADS', 'FAILED', 'Config not found'); 
        WHEN OTHERS THEN DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_error_and_raise('UPLOAD_ALL_BACKUPS', 'Error during upload: ' || SQLERRM); 
    END UPLOAD_ALL_BACKUPS; 
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_GITHUB_PKG;
/

----------------------------------------------------------------------
-- 5) APEX BACKUP PACKAGE (Secure application export)
----------------------------------------------------------------------
CREATE OR REPLACE PACKAGE DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_APEX_PKG AS 
    PROCEDURE BACKUP_APEX_APP_TO_GITHUB(p_app_id IN NUMBER); 
    PROCEDURE apex_backup_app_to_github(p_app_id IN NUMBER, p_github_token IN VARCHAR2, p_repo IN VARCHAR2, p_branch IN VARCHAR2 DEFAULT 'main', p_file_path IN VARCHAR2 DEFAULT NULL); 
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_APEX_PKG;
/

CREATE OR REPLACE PACKAGE BODY DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_APEX_PKG AS 
    PROCEDURE BACKUP_APEX_APP_TO_GITHUB(p_app_id IN NUMBER) IS 
        l_repo_owner VARCHAR2(200); l_repo_name VARCHAR2(200); l_branch VARCHAR2(200); l_cred_id VARCHAR2(200); l_token VARCHAR2(4000); 
    BEGIN 
        SELECT repo_owner, repo_name, branch, credential_static_id INTO l_repo_owner, l_repo_name, l_branch, l_cred_id FROM DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG WHERE config_id = (SELECT MAX(config_id) FROM DEVOPS_SEC_SYSTEM_ALL_L_DEVOPS_GITHUB_CONFIG); 
        l_token := DEVOPS_SEC_SYSTEM_ALL_SUB_UTILS_PKG.get_github_token(NVL(l_cred_id, 'GITHUB_TOKEN_CRED')); 
        apex_backup_app_to_github(p_app_id, l_token, l_repo_owner || '/' || l_repo_name, l_branch); 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('APEX_GITHUB', 'SUCCESS', 'App ' || p_app_id); 
    EXCEPTION WHEN OTHERS THEN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('APEX_GITHUB', 'FAILED', SQLERRM); 
    END BACKUP_APEX_APP_TO_GITHUB; 

    PROCEDURE apex_backup_app_to_github(p_app_id IN NUMBER, p_github_token IN VARCHAR2, p_repo IN VARCHAR2, p_branch IN VARCHAR2 DEFAULT 'main', p_file_path IN VARCHAR2 DEFAULT NULL) IS 
        l_file_path VARCHAR2(200) := NVL(p_file_path, 'apex/app_' || p_app_id || '_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') || '.sql'); 
        l_export_files APEX_T_EXPORT_FILES; l_file_blob BLOB; l_sha VARCHAR2(200); l_json CLOB; l_base64_content CLOB; 
    BEGIN 
        l_export_files := apex_export.get_application(p_application_id => p_app_id, p_split => FALSE, p_with_date => TRUE); 
        IF l_export_files.COUNT = 0 THEN RETURN; END IF; 
        l_file_blob := apex_util.clob_to_blob(l_export_files(1).contents); 
        l_base64_content := apex_util.blob_to_base64(l_file_blob); 
        
        -- Get SHA
        apex_web_service.clear_request_headers; 
        apex_web_service.set_request_headers(p_name_01 => 'Authorization', p_value_01 => 'token ' || p_github_token, p_name_02 => 'User-Agent', p_value_02 => 'Oracle-APEX'); 
        l_sha := json_value(apex_web_service.make_rest_request(p_url => 'https://api.github.com/repos/' || p_repo || '/contents/' || l_file_path, p_http_method => 'GET'), '$.sha'); 
        
        apex_json.initialize_clob_output; apex_json.open_object; apex_json.write('message', 'APEX backup ' || p_app_id); apex_json.write('content', l_base64_content); 
        IF l_sha IS NOT NULL THEN apex_json.write('sha', l_sha); END IF; 
        apex_json.write('branch', p_branch); apex_json.close_object; l_json := apex_json.get_clob_output; apex_json.free_output; 
        
        apex_web_service.clear_request_headers; 
        apex_web_service.set_request_headers(p_name_01 => 'Authorization', p_value_01 => 'token ' || p_github_token, p_name_02 => 'User-Agent', p_value_02 => 'Oracle-APEX', p_name_03 => 'Content-Type', p_value_03 => 'application/json'); 
        apex_web_service.make_rest_request(p_url => 'https://api.github.com/repos/' || p_repo || '/contents/' || l_file_path, p_http_method => 'PUT', p_body => l_json); 
    EXCEPTION WHEN OTHERS THEN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_error_and_raise('APEX_BACKUP_INTERNAL', 'Error APEX backup ' || p_app_id || ': ' || SQLERRM, FALSE); 
    END apex_backup_app_to_github; 
END DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_APEX_PKG;
/

----------------------------------------------------------------------
-- 6) CORE ORCHESTRATOR PACKAGE
----------------------------------------------------------------------
CREATE OR REPLACE PACKAGE DEVOPS_SEC_SYSTEM_ALL_SUB_CORE_PKG AS 
    PROCEDURE RUN_FULL_BACKUP; 
END DEVOPS_SEC_SYSTEM_ALL_SUB_CORE_PKG;
/

CREATE OR REPLACE PACKAGE BODY DEVOPS_SEC_SYSTEM_ALL_SUB_CORE_PKG AS 
    PROCEDURE RUN_FULL_BACKUP IS 
    BEGIN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_packages; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_procedures; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_functions; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_views; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_triggers; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_tables; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_sequences; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_indexes; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_constraints; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_grants; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_synonyms; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_types; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_mat_views; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_EXPORT_PKG.backup_all_scheduler_jobs; 
        
        -- Example app ID 105; adjust as needed or iterate through apps
        BEGIN
          DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_APEX_PKG.BACKUP_APEX_APP_TO_GITHUB(105); 
        EXCEPTION WHEN OTHERS THEN NULL; END;
        
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_GITHUB_PKG.UPLOAD_ALL_BACKUPS; 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('FULL_BACKUP', 'SUCCESS', 'Completed at ' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')); 
    EXCEPTION WHEN OTHERS THEN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_backup('FULL_BACKUP', 'FAILED', SQLERRM); RAISE; 
    END RUN_FULL_BACKUP; 
END DEVOPS_SEC_SYSTEM_ALL_SUB_CORE_PKG;
/

----------------------------------------------------------------------
-- 7) PUBLIC FACADE PACKAGE
----------------------------------------------------------------------
CREATE OR REPLACE PACKAGE DEVOPS_SEC_SYSTEM_ALL AS 
    PROCEDURE RUN_FULL_BACKUP; 
    PROCEDURE SET_GITHUB_CONFIG( 
        p_repo_owner    IN VARCHAR2, 
        p_repo_name     IN VARCHAR2, 
        p_credential_static_id IN VARCHAR2 DEFAULT 'GITHUB_TOKEN_CRED',
        p_branch        IN VARCHAR2 DEFAULT 'main', 
        p_base_path     IN VARCHAR2 DEFAULT '' 
    ); 
END DEVOPS_SEC_SYSTEM_ALL;
/

CREATE OR REPLACE PACKAGE BODY DEVOPS_SEC_SYSTEM_ALL AS 
    PROCEDURE RUN_FULL_BACKUP IS 
    BEGIN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_CORE_PKG.RUN_FULL_BACKUP; 
    EXCEPTION WHEN OTHERS THEN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_error_and_raise('RUN_FULL_BACKUP', 'Error executing full backup: ' || SQLERRM, FALSE); 
    END RUN_FULL_BACKUP; 
     
    PROCEDURE SET_GITHUB_CONFIG( 
        p_repo_owner    IN VARCHAR2, 
        p_repo_name     IN VARCHAR2, 
        p_credential_static_id IN VARCHAR2 DEFAULT 'GITHUB_TOKEN_CRED',
        p_branch        IN VARCHAR2 DEFAULT 'main', 
        p_base_path     IN VARCHAR2 DEFAULT '' 
    ) IS 
    BEGIN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_GITHUB_PKG.SET_GITHUB_CONFIG( 
            p_repo_owner => p_repo_owner, 
            p_repo_name => p_repo_name, 
            p_credential_static_id => p_credential_static_id, 
            p_branch => p_branch, 
            p_base_path => p_base_path 
        ); 
    EXCEPTION WHEN OTHERS THEN 
        DEVOPS_SEC_SYSTEM_ALL_SUB_BACKUP_LOG_PKG.log_error_and_raise('SET_GITHUB_CONFIG', 'Error setting GitHub config: ' || SQLERRM, FALSE); 
    END SET_GITHUB_CONFIG; 
END DEVOPS_SEC_SYSTEM_ALL;
/
