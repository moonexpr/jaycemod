//! A directed graph of nodes 0..n, each node's links kept in the order they
//! were added (a search that breaks ties by order depends on it), in two
//! arrays: where each node's links start, and every link's target.

#[derive(Debug, PartialEq, Eq)]
pub enum GraphError {
    /// A link names a node the graph does not have.
    NoSuchNode { from: u32, to: u32, nodes: u32 },
    /// A link was added before any node.
    LinkBeforeNode,
}

impl std::fmt::Display for GraphError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GraphError::NoSuchNode { from, to, nodes } => {
                write!(f, "a link from node {from} to {to}, of a graph of {nodes} nodes")
            }
            GraphError::LinkBeforeNode => write!(f, "a link added before any node"),
        }
    }
}

pub struct Graph {
    starts: Vec<u32>,
    targets: Vec<u32>,
}

/// Builds a graph a node at a time: a node, then its links in order.
#[derive(Default)]
pub struct Builder {
    starts: Vec<u32>,
    targets: Vec<u32>,
}

impl Builder {
    /// Starts the next node (numbered from 0) and returns its number.
    pub fn node(&mut self) -> u32 {
        self.starts.push(self.targets.len() as u32);
        self.starts.len() as u32 - 1
    }

    /// Adds a link from the latest node to `to`, which may come later.
    pub fn link(&mut self, to: u32) -> Result<usize, GraphError> {
        if self.starts.is_empty() {
            return Err(GraphError::LinkBeforeNode);
        }
        self.targets.push(to);
        Ok(self.targets.len() - 1)
    }

    pub fn nodes(&self) -> u32 {
        self.starts.len() as u32
    }

    /// The graph, or the first link to a node it lacks.
    pub fn finish(mut self) -> Result<Graph, GraphError> {
        let nodes = self.starts.len() as u32;
        for from in 0..nodes {
            let (start, end) = (self.starts[from as usize] as usize, self.end(from));
            for &to in &self.targets[start..end] {
                if to >= nodes {
                    return Err(GraphError::NoSuchNode { from, to, nodes });
                }
            }
        }
        self.starts.push(self.targets.len() as u32);
        Ok(Graph { starts: self.starts, targets: self.targets })
    }

    fn end(&self, node: u32) -> usize {
        self.starts
            .get(node as usize + 1)
            .map_or(self.targets.len(), |&end| end as usize)
    }
}

impl Graph {
    pub fn nodes(&self) -> u32 {
        self.starts.len() as u32 - 1
    }

    pub fn links(&self) -> usize {
        self.targets.len()
    }

    /// The link numbers of `node`'s links, in order.
    pub fn links_of(&self, node: u32) -> std::ops::Range<usize> {
        self.starts[node as usize] as usize..self.starts[node as usize + 1] as usize
    }

    pub fn target(&self, link: usize) -> u32 {
        self.targets[link]
    }

    /// `node`'s neighbours, in order.
    pub fn neighbors(&self, node: u32) -> &[u32] {
        &self.targets[self.links_of(node)]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_each_nodes_links_in_order() {
        let mut b = Builder::default();
        b.node();
        b.link(2).unwrap();
        b.link(1).unwrap();
        b.node();
        b.node();
        b.link(0).unwrap();
        let g = b.finish().unwrap();
        assert_eq!(g.nodes(), 3);
        assert_eq!(g.neighbors(0), &[2, 1]);
        assert_eq!(g.neighbors(1), &[] as &[u32]);
        assert_eq!(g.neighbors(2), &[0]);
        assert_eq!(g.links_of(2), 2..3);
        assert_eq!(g.target(1), 1);
    }

    #[test]
    fn refuses_a_link_to_a_missing_node() {
        let mut b = Builder::default();
        b.node();
        b.link(5).unwrap();
        assert_eq!(b.finish().err(), Some(GraphError::NoSuchNode { from: 0, to: 5, nodes: 1 }));
    }

    #[test]
    fn refuses_a_link_before_a_node() {
        assert_eq!(Builder::default().link(0), Err(GraphError::LinkBeforeNode));
    }
}
