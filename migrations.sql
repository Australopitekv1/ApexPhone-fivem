-- ============================================================
--  ApexPhone — migrations.sql
--  Run these once against an existing DB to bring it up to date.
--  New installs do NOT need this file — BootstrapDB handles it.
-- ============================================================

-- v3.1: hardware_modules column (HaaS feature)
ALTER TABLE `apexphone_phones`
    ADD COLUMN IF NOT EXISTS `hardware_modules` JSON DEFAULT '{}';

-- v3.1: widen pin / duress_pin columns for SHA-256 hex digest (64 chars)
ALTER TABLE `apexphone_phones`
    MODIFY COLUMN `pin`        VARCHAR(64) DEFAULT NULL,
    MODIFY COLUMN `duress_pin` VARCHAR(64) DEFAULT NULL;
