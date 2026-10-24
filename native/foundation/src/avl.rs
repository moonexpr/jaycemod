//! An ordered map of number keys on an AVL tree, nodes in an arena: the Lua
//! twin's algorithm (foundation/tree/avl.lua) step for step, rotations and
//! the successor taken on removal alike, so a tree built by the same calls
//! has the same shape and height.

const NIL: u32 = u32::MAX;

#[derive(Clone, Copy)]
struct Node {
    key: f64,
    value: u32,
    left: u32,
    right: u32,
    height: i32,
}

#[derive(Default)]
pub struct Avl {
    nodes: Vec<Node>,
    free: Vec<u32>,
    root: Option<u32>,
    size: usize,
}

impl Avl {
    fn node(&self, i: u32) -> &Node {
        &self.nodes[i as usize]
    }

    fn node_mut(&mut self, i: u32) -> &mut Node {
        &mut self.nodes[i as usize]
    }

    fn height_of(&self, i: u32) -> i32 {
        if i == NIL { 0 } else { self.node(i).height }
    }

    fn update(&mut self, i: u32) {
        let (l, r) = (self.node(i).left, self.node(i).right);
        self.node_mut(i).height = self.height_of(l).max(self.height_of(r)) + 1;
    }

    fn rotate_right(&mut self, i: u32) -> u32 {
        let left = self.node(i).left;
        self.node_mut(i).left = self.node(left).right;
        self.node_mut(left).right = i;
        self.update(i);
        self.update(left);
        left
    }

    fn rotate_left(&mut self, i: u32) -> u32 {
        let right = self.node(i).right;
        self.node_mut(i).right = self.node(right).left;
        self.node_mut(right).left = i;
        self.update(i);
        self.update(right);
        right
    }

    fn balance(&mut self, i: u32) -> u32 {
        self.update(i);
        let (l, r) = (self.node(i).left, self.node(i).right);
        let skew = self.height_of(l) - self.height_of(r);
        if skew > 1 {
            if self.height_of(self.node(l).left) < self.height_of(self.node(l).right) {
                let rotated = self.rotate_left(l);
                self.node_mut(i).left = rotated;
            }
            return self.rotate_right(i);
        }
        if skew < -1 {
            if self.height_of(self.node(r).right) < self.height_of(self.node(r).left) {
                let rotated = self.rotate_right(r);
                self.node_mut(i).right = rotated;
            }
            return self.rotate_left(i);
        }
        i
    }

    fn alloc(&mut self, key: f64, value: u32) -> u32 {
        let node = Node { key, value, left: NIL, right: NIL, height: 1 };
        match self.free.pop() {
            Some(i) => {
                self.nodes[i as usize] = node;
                i
            }
            None => {
                self.nodes.push(node);
                self.nodes.len() as u32 - 1
            }
        }
    }

    /// Returns the subtree with key set, whether it is new, and the value it
    /// replaced (when it was not).
    fn insert_at(&mut self, i: u32, key: f64, value: u32) -> (u32, Option<u32>) {
        if i == NIL {
            return (self.alloc(key, value), None);
        }
        let node_key = self.node(i).key;
        let replaced;
        if key < node_key {
            let (child, r) = self.insert_at(self.node(i).left, key, value);
            self.node_mut(i).left = child;
            replaced = r;
        } else if node_key < key {
            let (child, r) = self.insert_at(self.node(i).right, key, value);
            self.node_mut(i).right = child;
            replaced = r;
        } else {
            let old = self.node(i).value;
            self.node_mut(i).value = value;
            return (i, Some(old));
        }
        (self.balance(i), replaced)
    }

    fn remove_min(&mut self, i: u32) -> u32 {
        let left = self.node(i).left;
        if left == NIL {
            return self.node(i).right;
        }
        let child = self.remove_min(left);
        self.node_mut(i).left = child;
        self.balance(i)
    }

    fn min_node(&self, mut i: u32) -> u32 {
        while self.node(i).left != NIL {
            i = self.node(i).left;
        }
        i
    }

    /// Returns the subtree without key, and the removed node's value.
    fn remove_at(&mut self, i: u32, key: f64) -> (u32, Option<u32>) {
        if i == NIL {
            return (NIL, None);
        }
        let node_key = self.node(i).key;
        let removed;
        if key < node_key {
            let (child, r) = self.remove_at(self.node(i).left, key);
            self.node_mut(i).left = child;
            removed = r;
        } else if node_key < key {
            let (child, r) = self.remove_at(self.node(i).right, key);
            self.node_mut(i).right = child;
            removed = r;
        } else {
            let (left, right, value) = (self.node(i).left, self.node(i).right, self.node(i).value);
            self.free.push(i);
            if left == NIL {
                return (right, Some(value));
            }
            if right == NIL {
                return (left, Some(value));
            }
            let successor = self.min_node(right);
            let rest = self.remove_min(right);
            self.node_mut(successor).right = rest;
            self.node_mut(successor).left = left;
            return (self.balance(successor), Some(value));
        }
        (self.balance(i), removed)
    }

    fn root(&self) -> u32 {
        self.root.unwrap_or(NIL)
    }

    /// Sets key to value; returns the value it replaced, if the key was there.
    pub fn insert(&mut self, key: f64, value: u32) -> Option<u32> {
        let (root, replaced) = self.insert_at(self.root(), key, value);
        self.root = Some(root);
        if replaced.is_none() {
            self.size += 1;
        }
        replaced
    }

    /// Removes key; returns its value, if it was there.
    pub fn remove(&mut self, key: f64) -> Option<u32> {
        let (root, removed) = self.remove_at(self.root(), key);
        self.root = (root != NIL).then_some(root);
        if removed.is_some() {
            self.size -= 1;
        }
        removed
    }

    pub fn get(&self, key: f64) -> Option<u32> {
        let mut i = self.root();
        while i != NIL {
            let node = self.node(i);
            if key < node.key {
                i = node.left;
            } else if node.key < key {
                i = node.right;
            } else {
                return Some(node.value);
            }
        }
        None
    }

    pub fn len(&self) -> usize {
        self.size
    }

    pub fn is_empty(&self) -> bool {
        self.size == 0
    }

    pub fn height(&self) -> i32 {
        self.height_of(self.root())
    }

    fn entry(&self, i: u32) -> Option<(f64, u32)> {
        (i != NIL).then(|| (self.node(i).key, self.node(i).value))
    }

    pub fn min(&self) -> Option<(f64, u32)> {
        let root = self.root();
        if root == NIL { None } else { self.entry(self.min_node(root)) }
    }

    pub fn max(&self) -> Option<(f64, u32)> {
        let mut i = self.root();
        if i == NIL {
            return None;
        }
        while self.node(i).right != NIL {
            i = self.node(i).right;
        }
        self.entry(i)
    }

    /// The greatest key at or below `key`.
    #[allow(clippy::neg_cmp_op_on_partial_ord, reason = "the Lua twin's `not (a < b)`, NaN included")]
    pub fn floor(&self, key: f64) -> Option<(f64, u32)> {
        let (mut i, mut best) = (self.root(), NIL);
        while i != NIL {
            let node = self.node(i);
            if key < node.key {
                i = node.left;
            } else {
                best = i;
                if !(node.key < key) {
                    break;
                }
                i = node.right;
            }
        }
        self.entry(best)
    }

    /// The least key at or above `key`.
    #[allow(clippy::neg_cmp_op_on_partial_ord, reason = "the Lua twin's `not (a < b)`, NaN included")]
    pub fn ceiling(&self, key: f64) -> Option<(f64, u32)> {
        let (mut i, mut best) = (self.root(), NIL);
        while i != NIL {
            let node = self.node(i);
            if node.key < key {
                i = node.right;
            } else {
                best = i;
                if !(key < node.key) {
                    break;
                }
                i = node.left;
            }
        }
        self.entry(best)
    }

    /// The least key strictly above `key`: the in-order step after it.
    pub fn higher(&self, key: f64) -> Option<(f64, u32)> {
        let (mut i, mut best) = (self.root(), NIL);
        while i != NIL {
            let node = self.node(i);
            if key < node.key {
                best = i;
                i = node.left;
            } else {
                i = node.right;
            }
        }
        self.entry(best)
    }

    pub fn clear(&mut self) {
        *self = Avl::default();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn keys(avl: &Avl) -> Vec<f64> {
        let mut out = vec![];
        let mut at = avl.min();
        while let Some((key, _)) = at {
            out.push(key);
            at = avl.higher(key);
        }
        out
    }

    #[test]
    fn keys_in_order_and_a_key_set_again_replaces_its_value() {
        let mut avl = Avl::default();
        for k in [5.0, 2.0, 8.0, 1.0, 9.0, 3.0] {
            assert_eq!(avl.insert(k, k as u32), None);
        }
        assert_eq!(avl.insert(3.0, 33), Some(3));
        assert_eq!(keys(&avl), vec![1.0, 2.0, 3.0, 5.0, 8.0, 9.0]);
        assert_eq!((avl.len(), avl.get(3.0), avl.get(4.0)), (6, Some(33), None));
        assert_eq!((avl.min(), avl.max()), (Some((1.0, 1)), Some((9.0, 9))));
    }

    #[test]
    fn floor_ceiling_and_higher_find_the_nearest_keys() {
        let mut avl = Avl::default();
        for k in [10.0, 20.0, 30.0] {
            avl.insert(k, k as u32);
        }
        assert_eq!(avl.floor(25.0), Some((20.0, 20)));
        assert_eq!(avl.ceiling(25.0), Some((30.0, 30)));
        assert_eq!(avl.floor(20.0), Some((20.0, 20)));
        assert_eq!(avl.higher(20.0), Some((30.0, 30)));
        assert_eq!((avl.floor(5.0), avl.ceiling(35.0), avl.higher(30.0)), (None, None, None));
    }

    #[test]
    fn matches_a_sorted_map_through_thousands_of_changes_and_stays_balanced() {
        let (mut avl, mut model, mut x) = (Avl::default(), BTreeMap::new(), 99u64);
        for _ in 0..20000 {
            x = (x * 1103515245 + 12345) % 2147483648;
            let key = x % 900;
            if x % 3 == 0 {
                assert_eq!(avl.remove(key as f64), model.remove(&key));
            } else {
                assert_eq!(avl.insert(key as f64, x as u32), model.insert(key, x as u32));
            }
        }
        let expected: Vec<f64> = model.keys().map(|&k| k as f64).collect();
        assert_eq!(keys(&avl), expected);
        assert_eq!(avl.len(), model.len());
        assert!((avl.height() as f64) <= 1.45 * ((model.len() + 2) as f64).log2());
    }

    #[test]
    fn an_emptied_tree_is_empty() {
        let mut avl = Avl::default();
        avl.insert(1.0, 1);
        assert_eq!(avl.remove(1.0), Some(1));
        assert_eq!((avl.len(), avl.height(), avl.min(), avl.remove(1.0)), (0, 0, None, None));
        assert!(avl.is_empty());
    }
}
