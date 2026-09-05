-- mod-playerbots: preferred mount spell per bot character (`mount prefer <spellId>` chat order).
-- The module also runs this as CREATE TABLE IF NOT EXISTS on load, so the table exists even if
-- this file is never applied; it is tracked here so the schema is visible to the normal update
-- flow and to tooling, instead of appearing only as a side effect of worldserver start.

CREATE TABLE IF NOT EXISTS `playerbots_preferred_mounts` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `guid` INT(11) NOT NULL,
  `type` TINYINT(3) NOT NULL COMMENT '0: Ground, 1: Flying',
  `spellid` INT(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `guid` (`guid`),
  KEY `type` (`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
