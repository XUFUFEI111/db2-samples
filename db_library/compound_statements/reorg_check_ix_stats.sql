--# Copyright IBM Corp. All Rights Reserved.
--# SPDX-License-Identifier: Apache-2.0

/*
 * Write reorg check output for indexes to a table.  Also, run REORGs for indexes recommended
 * 
 * Db2 provides a REORGCHK_IX_STATS procedure that returns a dynamic result set.
 * 
 * This code writes that data to a persistent table which is much easier to work with
 * 
 */
 
DROP  TABLE DB_REORGCHK_IX_STATS
@

CREATE TABLE DB_REORGCHK_IX_STATS (
    TABSCHEMA             VARCHAR(128) NOT NULL
,   TABNAME               VARCHAR(128) NOT NULL
,   INDEX_SCHEMA          VARCHAR(128) NOT NULL
,   INDEX_NAME            VARCHAR(128) NOT NULL
,   DATAPARTITIONNAME     VARCHAR(128) NOT NULL
,   INDCARD               BIGINT   NOT NULL
,   NLEAF                 BIGINT   NOT NULL
,   NUM_EMPTY_LEAFS       BIGINT   NOT NULL
,   NLEVELS               INTEGER  NOT NULL
,   NUMRIDS_DELETED       BIGINT   NOT NULL
,   FULLKEYCARD           BIGINT   NOT NULL
,   LEAF_RECSIZE          BIGINT   NOT NULL
,   NONLEAF_RECSIZE       BIGINT   NOT NULL
,   LEAF_PAGE_OVERHEAD    BIGINT   NOT NULL
,   NONLEAF_PAGE_OVERHEAD BIGINT   NOT NULL
,   PCT_PAGES_SAVED       SMALLINT NOT NULL
,   F4                    INTEGER  NOT NULL
,   F5                    INTEGER  NOT NULL
,   F6                    INTEGER  NOT NULL
,   F7                    INTEGER  NOT NULL
,   F8                    INTEGER  NOT NULL
,   REORG                 CHAR(5)  NOT NULL
,   PRIMARY KEY (TABSCHEMA, TABNAME, INDEX_SCHEMA, INDEX_NAME, DATAPARTITIONNAME) ENFORCED
)
@

TRUNCATE TABLE DB_REORGCHK_IX_STATS IMMEDIATE
@

BEGIN
    DECLARE SQLSTATE CHAR(5);
    DECLARE V_TABSCHEMA             VARCHAR(128);
    DECLARE V_TABNAME               VARCHAR(128);
    DECLARE V_INDEX_SCHEMA          VARCHAR(128);
    DECLARE V_INDEX_NAME            VARCHAR(128);
    DECLARE V_DATAPARTITIONNAME     VARCHAR(128);
    DECLARE V_INDCARD               BIGINT;
    DECLARE V_NLEAF                 BIGINT;
    DECLARE V_NUM_EMPTY_LEAFS       BIGINT;
    DECLARE V_NLEVELS               INTEGER;
    DECLARE V_NUMRIDS_DELETED       BIGINT;
    DECLARE V_FULLKEYCARD           BIGINT;
    DECLARE V_LEAF_RECSIZE          BIGINT;
    DECLARE V_NONLEAF_RECSIZE       BIGINT;
    DECLARE V_LEAF_PAGE_OVERHEAD    BIGINT;
    DECLARE V_NONLEAF_PAGE_OVERHEAD BIGINT;
    DECLARE V_PCT_PAGES_SAVED       SMALLINT;
    DECLARE V_F4                    INTEGER;
    DECLARE V_F5                    INTEGER;
    DECLARE V_F6                    INTEGER;
    DECLARE V_F7                    INTEGER;
    DECLARE V_F8                    INTEGER;
    DECLARE V_REORG                 CHAR(5);
    DECLARE V1 RESULT_SET_LOCATOR VARYING;
    --
--    CALL SYSPROC.REORGCHK_IX_STATS('S', 'PAUL');  -- run for schema PAUL
--    CALL SYSPROC.REORGCHK_IX_STATS('T', 'ALL');   -- run for ALL tables
--    CALL SYSPROC.REORGCHK_IX_STATS('T', 'USER');  -- run for ALL USER tables
    CALL SYSPROC.REORGCHK_IX_STATS('T', 'SYSTEM');  -- run for ALL SYSTEM tables
--    
    ASSOCIATE RESULT SET LOCATOR (V1) WITH PROCEDURE SYSPROC.REORGCHK_IX_STATS;
    ALLOCATE C1 CURSOR FOR RESULT SET V1;
    --
    L1: LOOP
        FETCH C1                             INTO V_TABSCHEMA, V_TABNAME, V_INDEX_SCHEMA, V_INDEX_NAME, V_DATAPARTITIONNAME, V_INDCARD, V_NLEAF, V_NUM_EMPTY_LEAFS, V_NLEVELS, V_NUMRIDS_DELETED, V_FULLKEYCARD, V_LEAF_RECSIZE, V_NONLEAF_RECSIZE, V_LEAF_PAGE_OVERHEAD, V_NONLEAF_PAGE_OVERHEAD, V_PCT_PAGES_SAVED, V_F4, V_F5, V_F6, V_F7, V_F8, V_REORG;
        IF SQLSTATE<>'00000' THEN LEAVE L1; END IF;        
        INSERT INTO DB_REORGCHK_IX_STATS VALUES ( V_TABSCHEMA, V_TABNAME, V_INDEX_SCHEMA, V_INDEX_NAME, V_DATAPARTITIONNAME, V_INDCARD, V_NLEAF, V_NUM_EMPTY_LEAFS, V_NLEVELS, V_NUMRIDS_DELETED, V_FULLKEYCARD, V_LEAF_RECSIZE, V_NONLEAF_RECSIZE, V_LEAF_PAGE_OVERHEAD, V_NONLEAF_PAGE_OVERHEAD, V_PCT_PAGES_SAVED, V_F4, V_F5, V_F6, V_F7, V_F8, V_REORG) ;
    END LOOP L1;
  CLOSE C1;
END
@

SELECT 'CALL ADMIN_CMD(''REORG INDEXES ALL FOR TABLE "' || RTRIM(TABSCHEMA) || '"."' || TABNAME || '"'')' AS REORG_CMD
,   *
FROM
    DB_REORGCHK_IX_STATS
WHERE
    REORG <> '-----'
@

DROP   TABLE DB_REORG_LOG IF EXISTS
@

CREATE TABLE DB_REORG_LOG
(
    TS  TIMESTAMP NOT NULL
,   REORG_TYPE VARCHAR(16) NOT NULL
,   TABSCHEMA VARCHAR(128) NOT NULL
,   TABNAME   VARCHAR(128) NOT NULL
)
@

-- Now run the reorgs
--   Note that we use an ARRARY rather than a CURSOR as ADMIN_CMD REORG closes our cursors and  we get
--   SQL Error [24501]: The cursor specified in a FETCH statement or CLOSE statement is not open or a cursor variable in a cursor scalar function reference is not open
BEGIN
    DECLARE    TYPE VARCHAR_ARRAY AS VARCHAR(128)ARRAY[];
    DECLARE SCHEMAS VARCHAR_ARRAY;
    DECLARE TABLES  VARCHAR_ARRAY;
    DECLARE i INTEGER DEFAULT 1;
    --
    DECLARE LOAD_PENDING CONDITION FOR SQLSTATE '57016';    -- Skip LOAD pending tables 
    DECLARE NOT_ALLOWED  CONDITION FOR SQLSTATE '57007';    -- Skip Set Integrity Pending  tables  I.e. SQL0668N Operation not allowed
    --    DECLARE UNDEFINED_NAME CONDITION FOR SQLSTATE '42704';  -- Skip tables that no longer exist/not commited
    DECLARE CONTINUE HANDLER FOR LOAD_PENDING, NOT_ALLOWED BEGIN END;
    --
    SELECT
        ARRAY_AGG(TABSCHEMA ORDER BY TABSCHEMA, TABNAME)
     ,  ARRAY_AGG(TABNAME   ORDER BY TABSCHEMA, TABNAME)
            INTO  SCHEMAS, TABLES
    FROM
        DB_REORGCHK_IX_STATS
    WHERE
        REORG <> '-----'
    WITH UR;
    WHILE i <= CARDINALITY(TABLES)
    DO
          CALL ADMIN_CMD('REORG INDEXES ALL FOR TABLE "' || SCHEMAS[i] || '"."' || TABLES[i] || '"' );
          INSERT INTO DB_REORG_LOG VALUES (CURRENT_TIMESTAMP, 'INDEXES', SCHEMAS[1], TABLES[i]);
          CALL ADMIN_CMD('RUNSTATS ON TABLE "' || SCHEMAS[i] || '"."' || TABLES[i] || '" WITH DISTRIBUTION AND SAMPLED DETAILED INDEXES ALL');
          SET i = i + 1;
    END WHILE;
END
@

