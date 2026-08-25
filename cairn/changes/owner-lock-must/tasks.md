---
cairn: tasks
change: owner-lock-must
---

# Tasks

- [x] §8: the advisory lock becomes MUST, on `owner.lock`, held for the owner's lifetime, released by the operating system with the process.
- [x] §8: fail fast, naming the store, with the reason (a wait that outlasts a sync transaction is a stall with no signal, and the retrial policy is the caller's).
- [x] §8: the rule is about processes; several handles of one process share one lock.
- [x] §8: readers take neither lock; producers take a shared lock on `objects.lock` across the blob write and the enqueue.
- [x] §8: the network-filesystem paragraph names the advisory locks among what a share cannot be trusted with.
- [x] §3: the layout gains `owner.lock` and `objects.lock`, and says they are empty and lazily created.
- [x] Log entry.
- [ ] **Downstream, Android**: take both locks; the Java store is non-conformant until it does.
