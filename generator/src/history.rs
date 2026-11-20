//! # Histories
//!
//! A history is a list of steps, each an event and the store it leaves: a
//! remote's change, a producer's action drained, or a verb run against the
//! scripted remote, with the script it ran and what it answered. Each
//! step's model is the truth io-pimdir's store must hold after it, read
//! through the oracle; each run's pushes, outcomes and events are what its
//! engine must answer.

use std::collections::BTreeSet;

use crate::{
    engine::Run,
    model::{Collection, Kind, Model},
    profile::Draw,
    queue::{Action, RowState},
    remote::Remote,
};

/// One step of a history.
#[derive(Clone, Debug)]
pub struct Step {
    /// What happened.
    pub label: String,
    /// The verb run, if the step ran one.
    pub run: Option<Run>,
    /// The store after the step.
    pub model: Model,
}

/// A history over one source and one mailbox.
#[derive(Clone, Debug)]
pub struct History {
    /// Its steps, in order.
    pub steps: Vec<Step>,
}

/// The page size of a first round, small so seven members span three.
pub const PAGE: usize = 3;

impl History {
    /// One source and one mailbox (README.md, "Events and histories"): a
    /// first round in pages, an upgrade, remote changes, local changes
    /// drained and pushed, a flag changed on both sides, and a run with
    /// nothing left to do.
    pub fn mail(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        model.declare(Collection {
            id: String::from("work/INBOX"),
            account: Some(String::from("work")),
            kind: Some(Kind::Mail),
            name: String::from("INBOX"),
            role: Some(String::from("inbox")),
            source: Some(String::from("work-imap")),
            checkpoint: None,
            rounds: 0,
        });
        let mut remote = Remote::new("work-imap", "work/INBOX");
        for index in 0..7 {
            let flags = match index % 3 {
                0 => BTreeSet::new(),
                1 => set(&["\\Seen"]),
                _ => set(&["\\Seen", "$label1"]),
            };
            remote.deliver(draw.message(false).file(), flags);
        }

        let mut steps = vec![Step {
            label: String::from("a mailbox declared, never synced"),
            run: None,
            model: model.clone(),
        }];
        let mut record = |label: &str, run: Option<Run>, model: &Model| {
            steps.push(Step {
                label: String::from(label),
                run,
                model: model.clone(),
            });
        };

        let run = model.sync(&mut remote, PAGE);
        record("a first round in pages", Some(run), &model);

        let handles: Vec<String> = ["1", "2", "3"].map(String::from).to_vec();
        let run = model.upgrade(&remote, &handles);
        record("an upgrade fetching three bodies", Some(run), &model);

        let mut flagged = remote.members["1"].flags.clone();
        flagged.insert(String::from("\\Flagged"));
        remote.set_flags("1", flagged);
        remote.deliver(draw.message(false).file(), BTreeSet::new());
        remote.expunge("2");
        let mut unlabelled = remote.members["6"].flags.clone();
        unlabelled.remove("$label1");
        remote.set_flags("6", unlabelled);
        record("another client flags, delivers and expunges", None, &model);

        let (seq, flags) = model.bound_seq("work/INBOX", "3");
        let mut tagged = flags.clone();
        tagged.insert(String::from("$label2"));
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::SetFlags {
                seq,
                flags: tagged,
                base: Some(flags),
            },
        );
        model.drain(id);
        let (seq, _) = model.bound_seq("work/INBOX", "4");
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Remove {
                seq,
                if_match: None,
            },
        );
        model.drain(id);
        let message = draw.message(false);
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::Add {
                link_id: message.message_id.clone().unwrap_or_default(),
                flags: set(&["\\Seen"]),
                filed: message.file(),
            },
        );
        model.drain(id);
        record(
            "a flag change, a delete and a message filed, drained",
            None,
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record("a delta pulling and pushing", Some(run), &model);

        let mut labelled = remote.members["5"].flags.clone();
        labelled.insert(String::from("$Work"));
        remote.set_flags("5", labelled);
        let (seq, flags) = model.bound_seq("work/INBOX", "5");
        let mut answered = flags.clone();
        answered.insert(String::from("\\Answered"));
        let id = model.enqueue(
            "himalaya",
            "work/INBOX",
            Action::SetFlags {
                seq,
                flags: answered,
                base: Some(flags),
            },
        );
        model.drain(id);
        record("one member's flags changed on both sides", None, &model);

        let run = model.sync(&mut remote, PAGE);
        record("a delta merging both sides", Some(run), &model);

        let run = model.sync(&mut remote, PAGE);
        record("a delta with nothing left to do", Some(run), &model);

        Self { steps }
    }
}

impl Model {
    /// The `seq` and known flags of the item a handle binds in `collection`.
    fn bound_seq(&self, collection: &str, handle: &str) -> (i64, BTreeSet<String>) {
        let item = self
            .items
            .iter()
            .find(|item| {
                item.collection == collection
                    && item
                        .binding
                        .as_ref()
                        .is_some_and(|binding| binding.handle == handle)
            })
            .expect("a bound handle");
        (item.seq, item.flags.clone().unwrap_or_default())
    }
}

fn set(flags: &[&str]) -> BTreeSet<String> {
    flags.iter().map(|flag| String::from(*flag)).collect()
}

/// Whether every row of a model's queue was applied or parked.
pub fn drained(model: &Model) -> bool {
    model.queue.iter().all(|row| row.state != RowState::Pending)
}

#[cfg(test)]
mod tests {
    use std::{env, fs, process};

    use crate::{
        engine::{Event, Push},
        history::{History, PAGE, drained},
        model::State,
        oracle,
        spec::Spec,
        store::Store,
        writer,
    };

    fn history() -> History {
        History::mail(11)
    }

    #[test]
    fn every_step_leaves_a_store_the_statements_write_and_read_back() {
        let spec = Spec::load_default().unwrap();
        for (index, step) in history().steps.iter().enumerate() {
            let dir = env::temp_dir().join(format!(
                "pimdir-generator-history-{}-{index}",
                process::id()
            ));
            let _ = fs::remove_dir_all(&dir);
            let store = Store::create(&spec, &dir).unwrap();
            writer::materialise(&step.model, &store).unwrap();
            let expectations = oracle::expectations(&step.model, &spec).unwrap();
            let disagreements = oracle::check(&store, &expectations).unwrap();
            assert!(
                disagreements.is_empty(),
                "{}: {disagreements:#?}",
                step.label
            );
            let faults = oracle::feed::order(&store).unwrap();
            assert!(faults.is_empty(), "{}: {faults:#?}", step.label);
            drop(store);
            fs::remove_dir_all(&dir).unwrap();
        }
    }

    #[test]
    fn a_first_round_names_every_member_at_meta_page_by_page() {
        let history = history();
        let step = &history.steps[1];
        let run = step.run.as_ref().unwrap();

        assert_eq!(run.pages.len(), 7usize.div_ceil(PAGE));
        assert!(run.pages.iter().all(|page| page.complete));
        assert!(run.pages[0].checkpoint.is_some());
        assert!(run.pages[1..].iter().all(|page| page.checkpoint.is_none()));
        assert_eq!(run.pages.last().unwrap().cursor, None);
        assert_eq!(
            run.events
                .iter()
                .filter(|event| matches!(event, Event::Added(_)))
                .count(),
            7
        );
        assert!(run.pushes.is_empty());

        let collection = &step.model.collections["work/INBOX"];
        assert_eq!(collection.rounds, 1);
        assert_eq!(
            collection.checkpoint.as_deref(),
            run.pages[0].checkpoint.as_deref().map(str::as_bytes)
        );
        for item in &step.model.items {
            assert_eq!((item.level, item.object.is_none()), (1, true));
            assert_eq!(item.binding.as_ref().unwrap().round, Some(1));
        }
    }

    #[test]
    fn an_upgrade_fetches_a_body_into_the_item_and_its_base() {
        let history = history();
        let run = history.steps[2].run.as_ref().unwrap();
        assert_eq!(run.fetch.len(), 3);
        for item in history.steps[2]
            .model
            .items
            .iter()
            .filter(|item| item.object.is_some())
        {
            let binding = item.binding.as_ref().unwrap();
            assert_eq!(item.level, 2);
            assert_eq!(binding.base_object, item.object);
        }
    }

    #[test]
    fn a_delta_pulls_what_another_client_did_and_pushes_what_was_drained() {
        let history = history();
        assert!(drained(&history.steps[4].model));
        let step = &history.steps[5];
        let run = step.run.as_ref().unwrap();

        let kinds: Vec<&str> = run
            .pushes
            .iter()
            .map(|(push, _)| match push {
                Push::Add { .. } => "add",
                Push::Remove { .. } => "remove",
                Push::SetFlags { .. } => "set-flags",
            })
            .collect();
        assert_eq!(kinds, ["add", "set-flags", "remove"]);
        let Push::SetFlags { add, remove, .. } = &run.pushes[1].0 else {
            panic!("a flag push");
        };
        assert_eq!(add.iter().collect::<Vec<_>>(), ["$label2"]);
        assert!(remove.is_empty());

        assert!(run.events.contains(&Event::FlagsChanged(String::from("1"))));
        assert!(run.events.contains(&Event::FlagsChanged(String::from("6"))));
        let six = step
            .model
            .items
            .iter()
            .find(|item| {
                item.binding
                    .as_ref()
                    .is_some_and(|binding| binding.handle == "6")
            })
            .unwrap();
        assert!(
            !six.flags.as_ref().unwrap().contains("$label1"),
            "a flag the remote removed goes"
        );
        assert!(run.events.contains(&Event::Vanished(String::from("2"))));
        assert!(run.events.contains(&Event::Added(String::from("8"))));
        assert!(
            run.events
                .iter()
                .any(|event| matches!(event, Event::Created(_)))
        );

        for handle in ["2", "4"] {
            let gone = step.model.items.iter().find(|item| {
                history.steps[4].model.items.iter().any(|before| {
                    before.seq == item.seq
                        && before
                            .binding
                            .as_ref()
                            .is_some_and(|binding| binding.handle == handle)
                })
            });
            let gone = gone.unwrap();
            assert_eq!(
                gone.state,
                State::Retained {
                    by: Some(String::from("work-imap"))
                },
                "{handle}"
            );
        }
    }

    #[test]
    fn both_sides_merge_and_push_only_what_the_remote_lacks() {
        let history = history();
        let run = history.steps[7].run.as_ref().unwrap();
        assert_eq!(run.pushes.len(), 1);
        let Push::SetFlags {
            handle,
            add,
            remove,
        } = &run.pushes[0].0
        else {
            panic!("a flag push");
        };
        assert_eq!(handle, "5");
        assert_eq!(add.iter().collect::<Vec<_>>(), ["\\Answered"]);
        assert!(remove.is_empty());
        assert!(run.events.contains(&Event::FlagsChanged(String::from("5"))));

        let item = history.steps[7]
            .model
            .items
            .iter()
            .find(|item| {
                item.binding
                    .as_ref()
                    .is_some_and(|binding| binding.handle == "5")
            })
            .unwrap();
        let flags = item.flags.as_ref().unwrap();
        assert!(flags.contains("$Work") && flags.contains("\\Answered"));
    }

    #[test]
    fn a_run_after_convergence_changes_nothing() {
        let history = history();
        let last = &history.steps[8];
        let run = last.run.as_ref().unwrap();
        assert!(run.pushes.is_empty(), "{:?}", run.pushes);
        assert!(run.events.is_empty(), "{:?}", run.events);
    }
}
