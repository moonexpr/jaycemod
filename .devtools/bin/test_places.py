import unittest

import places
from places import Door, Space

RED, BLU = "RED", "BLU"
STEP = 400.0


class Map:
    """A partition by hand: rooms at (x, y) * STEP, joined by door() or through a corridor()."""

    def __init__(self):
        self.rooms, self.passages, self.seals = {}, {}, []

    def room(self, rid, x, y=0, outdoor=False):
        self.rooms[rid] = Space(rid, True, (x * STEP, y * STEP, 0.0), [], outdoor)
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
        self.passages[pid] = Space(pid, False, mid, [Door(pa, (a,), None), Door(pb, (b,), None)], False)
        self.rooms[a].doors.append(Door(pa, (b,), pid))
        self.rooms[b].doors.append(Door(pb, (a,), pid))
        return self

    def seal(self, a, b):
        """A respawn room visualizer over the door between rooms a and b."""
        x, y, z = self.between(self.rooms[a].center, self.rooms[b].center)
        self.seals.append(((x - 8, y - 64, z), (x + 8, y + 64, z + 128)))
        return self

    @staticmethod
    def keyed(spawns):
        """spawns: team -> room ids, or ("passage", id) for a corridor inside a spawn."""
        return {t: [k if isinstance(k, tuple) else ("room", k) for k in ids] for t, ids in spawns.items()}

    def start(self, spawns, objectives):
        return places.Start(list(self.rooms.values()), list(self.passages.values()), self.keyed(spawns), objectives,
                            self.seals)

    def places(self, spawns):
        """Each room's place: room id -> places.Place."""
        found = places.Places(list(self.rooms.values()), list(self.passages.values()), self.keyed(spawns))
        return {key[1]: place for place in found for key in place.members if key[0] == "room"}


def Line():
    """Two buildings and a yard between: RED's (its spawn 1, a room behind it 7, and 2), the yard with the
    objective (3) in the middle and a field far off both teams' ways (8), and BLU's (its spawn 5, 4, and a
    room off BLU's way, 6)."""
    m = Map()
    for rid, x, y in ((7, -1, 0), (1, 0, 0), (2, 1, 0), (4, 3, 0), (5, 4, 0), (6, 3, 1)):
        m.room(rid, x, y)
    m.room(3, 2, 0, outdoor=True).room(8, 2, 3, outdoor=True)
    for a, b in ((7, 1), (1, 2), (2, 3), (3, 4), (4, 5), (4, 6), (3, 8)):
        m.door(a, b)
    return m


SPAWNS = {RED: [1], BLU: [5]}


def Sealed():
    """The line with both spawns sealed at their doors by respawn room visualizers."""
    return Line().seal(1, 2).seal(4, 5)


class StartTest(unittest.TestCase):
    def test_a_teams_spawn_rooms_and_the_rooms_the_enemy_reaches_only_through_them_are_its_restricted_ground(self):
        c = Sealed().start(SPAWNS, [3])
        self.assertEqual(c[1], places.Placed(places.RESTRICTED, RED))
        self.assertEqual(c[7], places.Placed(places.RESTRICTED, RED), "behind RED's spawn")
        self.assertEqual(c[5], places.Placed(places.RESTRICTED, BLU))

    def test_a_spawn_whose_doors_no_visualizer_seals_is_no_restricted_ground(self):
        c = Line().start(SPAWNS, [3])
        self.assertNotIn(places.RESTRICTED, {p.cls for p in c.values()})
        self.assertEqual(c[1], places.Placed(places.STRONGHOLD, RED), "RED's own ground its ways start from")

    def test_every_unsealed_spawn_room_is_its_teams_stronghold_ways_or_not(self):
        c = Line().start({RED: [1, 7], BLU: [5]}, [3])
        self.assertEqual(c[7], places.Placed(places.STRONGHOLD, RED), "a spawn room no way starts from")

    def test_a_corridor_inside_the_spawn_is_its_ground_too_sealed_at_its_far_door(self):
        m = Map()
        for rid, x in ((1, 0), (2, 2), (3, 3), (5, 5)):
            m.room(rid, x)
        m.corridor(1, 1, 2).door(2, 3).door(3, 5).seal(2, 3)  # RED's spawn: room 1 and its corridor to room 2
        c = m.start({RED: [1, ("passage", 1), 2], BLU: [5]}, [3])
        self.assertEqual(c[1], places.Placed(places.RESTRICTED, RED), "sealed at room 2's door, not the corridor's")
        self.assertEqual(c[2], places.Placed(places.RESTRICTED, RED))

    def test_one_door_left_unsealed_opens_the_spawn(self):
        c = Line().seal(4, 5).start(SPAWNS, [3])
        self.assertEqual(c[5], places.Placed(places.RESTRICTED, BLU), "BLU's spawn, sealed")
        self.assertNotEqual(c[1].cls, places.RESTRICTED, "RED's spawn, open")
        self.assertNotEqual(c[7].cls, places.RESTRICTED, "nor what lies behind it")

    def test_an_objectives_room_is_a_highway_and_no_ones(self):
        self.assertEqual(Line().start(SPAWNS, [3])[3], places.Placed(places.HIGHWAY, None))

    def test_a_room_only_one_teams_ways_cross_nearer_that_team_is_its_stronghold(self):
        c = Line().start(SPAWNS, [3])
        self.assertEqual(c[2], places.Placed(places.STRONGHOLD, RED))
        self.assertEqual(c[4], places.Placed(places.STRONGHOLD, BLU))

    def test_off_every_way_far_from_both_spawns_is_unoccupied(self):
        self.assertEqual(Line().start(SPAWNS, [3])[8].cls, places.UNOCCUPIED, "far out from the middle")

    def test_the_final_pass_makes_a_room_left_wilds_outdoors_and_unoccupied_indoors(self):
        def shed(outdoor):  # a yard off RED's building (10), and a shed beyond it (11), no team's place
            return Line().room(10, 1, -1, outdoor=True).room(11, 1, -1.5, outdoor=outdoor).door(2, 10).door(10, 11)
        self.assertEqual(shed(False).start(SPAWNS, [3])[11].cls, places.UNOCCUPIED, "under a roof")
        self.assertEqual(shed(True).start(SPAWNS, [3])[11].cls, places.WILDS, "out of doors")

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

    def test_a_room_in_a_teams_building_off_every_way_is_its_stronghold_not_unoccupied(self):
        self.assertEqual(Line().start(SPAWNS, [3])[6], places.Placed(places.STRONGHOLD, BLU),
                         "off BLU's way, but inside BLU's building")

    def test_an_enemy_stronghold_inside_a_teams_building_is_commons(self):
        # RED's building runs 1, 2, 12, 13 to a yard (14) by BLU's (5); the objective in RED's (2)
        m = Map()
        for rid, x in ((1, 0), (2, 1), (12, 2), (13, 3), (5, 5)):
            m.room(rid, x)
        m.room(14, 4, 0, outdoor=True)
        for a, b in ((1, 2), (2, 12), (12, 13), (13, 14), (14, 5)):
            m.door(a, b)
        c = m.start(SPAWNS, [2])
        self.assertEqual(c[13].cls, places.COMMONS, "nearer BLU and only on BLU's way, but in RED's building")

    def test_corridors_carry_the_ways_but_are_given_no_class(self):
        m = Map().room(1, 0).room(2, 1).room(3, 2).room(5, 4).door(1, 2).door(2, 3).corridor(1, 3, 5)
        c = m.start(SPAWNS, [3])
        self.assertEqual(c[3].cls, places.HIGHWAY)
        self.assertEqual(c[2], places.Placed(places.STRONGHOLD, RED))
        self.assertEqual(sorted(c), [1, 2, 3, 5], "rooms alone")

    def test_with_no_objectives_the_ways_go_to_the_enemys_spawns(self):
        self.assertEqual(Line().start(SPAWNS, [])[3].cls, places.HIGHWAY, "the middle, on every way")

    def test_a_room_no_team_reaches_is_left_to_the_final_pass(self):
        self.assertEqual(Line().room(20, 9, 9, outdoor=True).start(SPAWNS, [3])[20].cls, places.WILDS)
        self.assertEqual(Line().room(20, 9, 9).start(SPAWNS, [3])[20].cls, places.UNOCCUPIED)


class PlacesTest(unittest.TestCase):
    def test_a_building_with_a_teams_spawn_is_its_and_the_yard_between_no_ones(self):
        p = Line().places(SPAWNS)
        self.assertIs(p[1], p[7])
        self.assertIs(p[1], p[2], "RED's building, one place")
        self.assertEqual((p[1].kind, p[1].owner), (places.BUILDING, RED))
        self.assertEqual((p[5].kind, p[5].owner), (places.BUILDING, BLU))
        self.assertIs(p[4], p[6])
        self.assertEqual((p[3].kind, p[3].owner), (places.GROUNDS, None), "the yard between")
        self.assertIs(p[3], p[8], "the yard and the field beyond it, one grounds")

    def test_a_building_holding_both_spawns_is_split_where_their_walks_meet(self):
        m = Map()
        for rid, x in ((1, 0), (2, 1), (3, 2), (4, 3), (5, 4)):
            m.room(rid, x)
        for a, b in ((1, 2), (2, 3), (3, 4), (4, 5)):
            m.door(a, b)
        p = m.places(SPAWNS)
        self.assertEqual(p[2].owner, RED)
        self.assertIs(p[1], p[2])
        self.assertEqual(p[4].owner, BLU)
        self.assertEqual(p[3].owner, None, "the middle, as near one side as the other: no one's")
        self.assertEqual(len({id(place) for place in p.values()}), 3)

    def test_a_building_with_no_spawn_is_no_ones(self):
        p = Line().room(10, 1, -1, outdoor=True).room(11, 1, -2).door(2, 10).door(10, 11).places(SPAWNS)
        self.assertEqual((p[11].kind, p[11].owner), (places.BUILDING, None))


if __name__ == "__main__":
    unittest.main()
