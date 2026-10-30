import unittest

import places
from places import Door, Space

RED, BLU = "RED", "BLU"
STEP = 400.0


class Map:
    """A partition by hand: rooms at (x, y) * STEP, joined by door() or through a corridor()."""

    def __init__(self):
        self.rooms, self.passages = {}, {}

    def room(self, rid, x, y=0):
        self.rooms[rid] = Space(rid, True, (x * STEP, y * STEP, 0.0), [])
        return self

    @staticmethod
    def between(a, b):
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.0)

    def door(self, a, b):
        pos = self.between(self.rooms[a].center, self.rooms[b].center)
        self.rooms[a].doors.append(Door(pos, (b,), None))
        self.rooms[b].doors.append(Door(pos, (a,), None))
        return self

    def corridor(self, pid, a, b):
        ca, cb = self.rooms[a].center, self.rooms[b].center
        mid = self.between(ca, cb)
        pa, pb = self.between(ca, mid), self.between(cb, mid)
        self.passages[pid] = Space(pid, False, mid, [Door(pa, (a,), None), Door(pb, (b,), None)])
        self.rooms[a].doors.append(Door(pa, (b,), pid))
        self.rooms[b].doors.append(Door(pb, (a,), pid))
        return self

    def start(self, spawns, objectives):
        return places.Start(list(self.rooms.values()), list(self.passages.values()), spawns, objectives)


def Line():
    """RED's spawn (1) with a room behind it (7), out to the objective (3) in the middle and on to BLU's
    spawn (5); a dead end (6) by BLU's side, and a room far off both teams' ways (8), out from the middle."""
    m = Map()
    for rid, x, y in ((7, -1, 0), (1, 0, 0), (2, 1, 0), (3, 2, 0), (4, 3, 0), (5, 4, 0), (6, 3, 1), (8, 2, 3)):
        m.room(rid, x, y)
    for a, b in ((7, 1), (1, 2), (2, 3), (3, 4), (4, 5), (4, 6), (3, 8)):
        m.door(a, b)
    return m


SPAWNS = {RED: [1], BLU: [5]}


class StartTest(unittest.TestCase):
    def test_a_teams_spawn_rooms_and_the_rooms_the_enemy_reaches_only_through_them_are_its_restricted_ground(self):
        c = Line().start(SPAWNS, [3])
        self.assertEqual(c[1], places.Placed(places.RESTRICTED, RED))
        self.assertEqual(c[7], places.Placed(places.RESTRICTED, RED), "behind RED's spawn")
        self.assertEqual(c[5], places.Placed(places.RESTRICTED, BLU))

    def test_an_objectives_room_is_a_highway_and_no_ones(self):
        self.assertEqual(Line().start(SPAWNS, [3])[3], places.Placed(places.HIGHWAY, None))

    def test_a_room_only_one_teams_ways_cross_nearer_that_team_is_its_stronghold(self):
        c = Line().start(SPAWNS, [3])
        self.assertEqual(c[2], places.Placed(places.STRONGHOLD, RED))
        self.assertEqual(c[4], places.Placed(places.STRONGHOLD, BLU))

    def test_off_every_way_far_from_both_spawns_is_unoccupied_and_near_a_spawn_wilds(self):
        c = Line().start(SPAWNS, [3])
        self.assertEqual(c[8].cls, places.UNOCCUPIED, "far out from the middle")
        self.assertEqual(c[6].cls, places.WILDS, "beside BLU's way, near its spawn: the final pass")

    def test_no_room_is_an_outpost_at_the_start_an_outpost_needs_a_claim(self):
        self.assertNotIn(places.OUTPOST, {p.cls for p in Line().start(SPAWNS, [3]).values()})

    def test_a_room_both_teams_cross_on_some_ways_is_commons_on_most_a_highway(self):
        def crossing():
            m = Map()
            for rid, x, y in ((1, 0, 0), (2, 1, 0), (3, 2, 0), (4, 3, 0), (5, 4, 0), (10, 2, -1), (9, 2, -2)):
                m.room(rid, x, y)
            for a, b in ((1, 2), (2, 3), (3, 4), (4, 5), (2, 10), (4, 10), (10, 9)):
                m.door(a, b)
            return m
        self.assertEqual(crossing().start(SPAWNS, [3, 9])[10].cls, places.COMMONS, "on half the ways")
        self.assertEqual(crossing().start(SPAWNS, [9])[10].cls, places.HIGHWAY, "on every way to the one objective")

    def test_a_room_on_most_of_one_teams_ways_not_its_own_ground_is_a_highway(self):
        c = Line().start(SPAWNS, [2])  # the objective by RED's spawn: BLU comes all the way across
        self.assertEqual(c[3].cls, places.HIGHWAY, "on BLU's every way, as near RED as BLU")
        self.assertEqual(c[4], places.Placed(places.STRONGHOLD, BLU), "BLU's own side stays its stronghold")

    def test_corridors_carry_the_ways_but_are_given_no_class(self):
        m = Map().room(1, 0).room(2, 1).room(3, 2).room(5, 4).door(1, 2).door(2, 3).corridor(1, 3, 5)
        c = m.start(SPAWNS, [3])
        self.assertEqual(c[3].cls, places.HIGHWAY)
        self.assertEqual(c[2], places.Placed(places.STRONGHOLD, RED))
        self.assertEqual(sorted(c), [1, 2, 3, 5], "rooms alone")

    def test_with_no_objectives_the_ways_go_to_the_enemys_spawns(self):
        self.assertEqual(Line().start(SPAWNS, [])[3].cls, places.HIGHWAY, "the middle, on every way")

    def test_a_room_no_team_reaches_is_wilds(self):
        self.assertEqual(Line().room(20, 9, 9).start(SPAWNS, [3])[20].cls, places.WILDS)


if __name__ == "__main__":
    unittest.main()
