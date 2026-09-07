-- mod-prabowow: characters whose starting zone has already been skipped.
--
-- The skip runs on login and must fire exactly once per character. One row here is
-- that marker; deleting a row lets the feature run again for that character on their
-- next login, which is the supported way to redo it by hand.

CREATE TABLE IF NOT EXISTS `character_startzone_skip` (
  `guid` int unsigned NOT NULL COMMENT 'characters.guid',
  `profile` tinyint unsigned NOT NULL COMMENT '0 = DeathKnight, 1 = Worgen, 2 = Goblin',
  `applied_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'when the skip was applied',
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COMMENT='mod-prabowow: starting zone skipped';
