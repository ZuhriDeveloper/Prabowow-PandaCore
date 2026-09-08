-- Smooth the MoP creature health curve above level 70.
--
-- 2026_08_17_world_00.sql rebuilt creature_classlevelstats with per-expansion
-- basehp columns, and Creature.cpp now reads basehp4 for every creature
-- regardless of creature_template.expansion. The basehp4 column was stitched
-- together from several sources and breaks above level 70:
--
--   level 71-72   continue the level 68-70 BC values (+3.4% per level)
--   level 73-74   jump to 2x those values (+107% at level 73)
--   level 75-84   jump again to a flat 121029-135552 plateau (+482% at
--                 level 75, then a linear +1613 per level)
--
-- Two rows also lose their class scaling: level 74 class 2 sits at 70454 while
-- classes 1/4 sit at 20796, and levels 75-83 give class 8 the class 1 value
-- instead of the 0.8x it carries at every other level.
--
-- The plateau makes a level 75 mob roughly as tough as a level 84 one and
-- about 11x its historical value, which is what players report as inflated
-- health in the Northrend and Cataclysm level range.
--
-- Levels 1-70 and 85+ are left untouched: they are already smooth, and level
-- 90 at 393941 matches retail 5.4.8. This replaces levels 71-84 with a
-- geometric ramp between the two good anchors, level 70 (8982) and level 85
-- (158079), which works out to +21.07% per level -- in the same family as the
-- +16.6% to +26.2% the curve already uses across levels 85-90. Class 8 keeps
-- its 0.8x ratio; classes 1, 2 and 4 stay equal.
--
-- Re-runnable: every row is set to its final value regardless of current state.

UPDATE `creature_classlevelstats` SET `basehp4`=10874 WHERE `level`=71 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=10874 WHERE `level`=71 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=10874 WHERE `level`=71 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=8699 WHERE `level`=71 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=13166 WHERE `level`=72 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=13166 WHERE `level`=72 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=13166 WHERE `level`=72 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=10533 WHERE `level`=72 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=15939 WHERE `level`=73 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=15939 WHERE `level`=73 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=15939 WHERE `level`=73 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=12751 WHERE `level`=73 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=19298 WHERE `level`=74 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=19298 WHERE `level`=74 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=19298 WHERE `level`=74 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=15438 WHERE `level`=74 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=23364 WHERE `level`=75 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=23364 WHERE `level`=75 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=23364 WHERE `level`=75 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=18691 WHERE `level`=75 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=28286 WHERE `level`=76 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=28286 WHERE `level`=76 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=28286 WHERE `level`=76 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=22629 WHERE `level`=76 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=34246 WHERE `level`=77 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=34246 WHERE `level`=77 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=34246 WHERE `level`=77 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=27397 WHERE `level`=77 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=41461 WHERE `level`=78 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=41461 WHERE `level`=78 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=41461 WHERE `level`=78 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=33169 WHERE `level`=78 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=50197 WHERE `level`=79 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=50197 WHERE `level`=79 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=50197 WHERE `level`=79 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=40158 WHERE `level`=79 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=60773 WHERE `level`=80 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=60773 WHERE `level`=80 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=60773 WHERE `level`=80 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=48618 WHERE `level`=80 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=73577 WHERE `level`=81 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=73577 WHERE `level`=81 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=73577 WHERE `level`=81 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=58862 WHERE `level`=81 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=89079 WHERE `level`=82 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=89079 WHERE `level`=82 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=89079 WHERE `level`=82 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=71263 WHERE `level`=82 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=107847 WHERE `level`=83 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=107847 WHERE `level`=83 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=107847 WHERE `level`=83 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=86278 WHERE `level`=83 AND `class`=8;

UPDATE `creature_classlevelstats` SET `basehp4`=130569 WHERE `level`=84 AND `class`=1;
UPDATE `creature_classlevelstats` SET `basehp4`=130569 WHERE `level`=84 AND `class`=2;
UPDATE `creature_classlevelstats` SET `basehp4`=130569 WHERE `level`=84 AND `class`=4;
UPDATE `creature_classlevelstats` SET `basehp4`=104455 WHERE `level`=84 AND `class`=8;

-- Levels 89 and 93 carry the same lost class-8 scaling as levels 75-83: class 8
-- repeats the class 1 value instead of 0.8x it, so those mobs sit 25% above the
-- rest of the curve. The class 1/2/4 values there are fine and are left alone.
--
-- Not touched: levels 94-95 class 8 (0.729x and 0.711x) and levels 91-95
-- class 4 sit *below* their expected share rather than above, so they do not
-- contribute to the inflated-health reports and are left for a separate pass.

UPDATE `creature_classlevelstats` SET `basehp4`=261573 WHERE `level`=89 AND `class`=8;
UPDATE `creature_classlevelstats` SET `basehp4`=348910 WHERE `level`=93 AND `class`=8;
