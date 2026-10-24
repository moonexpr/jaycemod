//! A binary min-heap of numbers keyed by numbers: the lowest key comes out
//! first, and of equal keys the one pushed first, so a search ordered by it
//! breaks ties the way NavAreaBuildPath does without a push count of its own.

#[derive(Default)]
pub struct Heap {
    entries: Vec<Entry>,
    pushed: u64,
}

#[derive(Clone, Copy)]
struct Entry {
    key: f64,
    seq: u64,
    value: f64,
}

impl Entry {
    fn before(&self, other: &Entry) -> bool {
        self.key < other.key || (self.key == other.key && self.seq < other.seq)
    }
}

impl Heap {
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn clear(&mut self) {
        self.entries.clear();
        self.pushed = 0;
    }

    pub fn push(&mut self, key: f64, value: f64) {
        self.pushed += 1;
        let entry = Entry { key, seq: self.pushed, value };
        let mut i = self.entries.len();
        self.entries.push(entry);
        while i > 0 {
            let parent = (i - 1) / 2;
            if !entry.before(&self.entries[parent]) {
                break;
            }
            self.entries[i] = self.entries[parent];
            i = parent;
        }
        self.entries[i] = entry;
    }

    /// The first entry's (value, key), left in.
    pub fn peek(&self) -> Option<(f64, f64)> {
        self.entries.first().map(|e| (e.value, e.key))
    }

    /// The first entry's (value, key), taken out.
    pub fn pop(&mut self) -> Option<(f64, f64)> {
        let top = *self.entries.first()?;
        let last = self.entries.pop().expect("a heap with a first entry has a last");
        let n = self.entries.len();
        if n > 0 {
            let mut i = 0;
            loop {
                let mut child = 2 * i + 1;
                if child >= n {
                    break;
                }
                if child + 1 < n && self.entries[child + 1].before(&self.entries[child]) {
                    child += 1;
                }
                if !self.entries[child].before(&last) {
                    break;
                }
                self.entries[i] = self.entries[child];
                i = child;
            }
            self.entries[i] = last;
        }
        Some((top.value, top.key))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pops_lowest_key_first() {
        let mut heap = Heap::default();
        for (key, value) in [(5.0, 50.0), (1.0, 10.0), (3.0, 30.0), (4.0, 40.0), (2.0, 20.0)] {
            heap.push(key, value);
        }
        let popped: Vec<f64> = std::iter::from_fn(|| heap.pop().map(|(v, _)| v)).collect();
        assert_eq!(popped, vec![10.0, 20.0, 30.0, 40.0, 50.0]);
    }

    #[test]
    fn equal_keys_come_out_in_push_order() {
        let mut heap = Heap::default();
        for value in 1..=40 {
            heap.push((value % 3) as f64, value as f64);
        }
        let mut last: Option<(f64, f64)> = None;
        while let Some((value, key)) = heap.pop() {
            if let Some((last_value, last_key)) = last {
                assert!(key > last_key || (key == last_key && value > last_value));
            }
            last = Some((value, key));
        }
    }

    #[test]
    fn empty_heap_pops_and_peeks_nothing() {
        let mut heap = Heap::default();
        assert_eq!(heap.pop(), None);
        assert_eq!(heap.peek(), None);
        heap.push(1.0, 2.0);
        assert_eq!(heap.peek(), Some((2.0, 1.0)));
        assert_eq!(heap.len(), 1);
        heap.clear();
        assert!(heap.is_empty());
    }

    #[test]
    fn matches_a_sort_on_many_values() {
        let mut heap = Heap::default();
        let mut keys: Vec<f64> = (0..1000u64).map(|i| ((i * 7919) % 1009) as f64).collect();
        for &key in &keys {
            heap.push(key, key);
        }
        keys.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let popped: Vec<f64> = std::iter::from_fn(|| heap.pop().map(|(_, k)| k)).collect();
        assert_eq!(popped, keys);
    }
}
