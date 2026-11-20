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
    body::Card,
    engine::Run,
    model::{Collection, Kind, Model},
    name::ObjectName,
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

    /// One source and one address book over DAV (README.md, "Events and
    /// histories"): a first round carrying bodies, a body edited on the
    /// server and pulled, one edited locally and pushed gated on its
    /// revision, one edited on both sides and recorded in conflict, a
    /// person's resolution pushed, a delete each way, and a run with
    /// nothing left to do.
    pub fn cards(seed: u64) -> Self {
        let mut draw = Draw::new(seed);
        let mut model = Model::new();
        model.declare(Collection {
            id: String::from("work/contacts"),
            account: Some(String::from("work")),
            kind: Some(Kind::Contact),
            name: String::from("Contacts"),
            role: Some(String::from("default")),
            source: Some(String::from("work-carddav")),
            checkpoint: None,
            rounds: 0,
        });
        let mut remote = Remote::dav("work-carddav", "work/contacts");
        let mut cards = Vec::new();
        for _ in 0..5 {
            let card = draw.card();
            remote.deliver(card.file(), BTreeSet::new());
            cards.push(card);
        }
        let renamed = |card: &Card, name: &str| Card {
            name: String::from(name),
            ..card.clone()
        };

        let mut steps = vec![Step {
            label: String::from("an address book declared, never synced"),
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
        record("a first round carrying every body", Some(run), &model);

        remote.edit("r1.vcf", renamed(&cards[0], "Edited On The Server").file());
        let (seq, object) = model.bound_card("work/contacts", "r2.vcf");
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: renamed(&cards[1], "Edited Here").file(),
                if_match: Some(object),
                resolves: None,
            },
        );
        model.drain(id);
        record(
            "a body edited on the server, another edited here",
            None,
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record(
            "a delta pulling one body and pushing the other",
            Some(run),
            &model,
        );

        remote.edit("r3.vcf", renamed(&cards[2], "Their Version").file());
        let (seq, object) = model.bound_card("work/contacts", "r3.vcf");
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: renamed(&cards[2], "Our Version").file(),
                if_match: Some(object),
                resolves: None,
            },
        );
        model.drain(id);
        record("one body edited on both sides", None, &model);

        let run = model.sync(&mut remote, PAGE);
        record("a delta recording the conflict", Some(run), &model);

        let (seq, _) = model.bound_card("work/contacts", "r3.vcf");
        let diverging = model.items[model.bound_index("work/contacts", "r3.vcf")]
            .binding
            .as_ref()
            .and_then(|binding| binding.conflict_object.clone());
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Update {
                seq,
                filed: renamed(&cards[2], "Our Merged Version").file(),
                if_match: None,
                resolves: diverging.map(|name| vec![name]),
            },
        );
        model.drain(id);
        let (seq, object) = model.bound_card("work/contacts", "r4.vcf");
        let id = model.enqueue(
            "cardamum",
            "work/contacts",
            Action::Remove {
                seq,
                if_match: Some(object),
            },
        );
        model.drain(id);
        remote.expunge("r5.vcf");
        record(
            "a person's resolution, a delete here and one there",
            None,
            &model,
        );

        let run = model.sync(&mut remote, PAGE);
        record(
            "a delta pushing the resolution and the delete",
            Some(run),
            &model,
        );

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

    fn bound_index(&self, collection: &str, handle: &str) -> usize {
        self.items
            .iter()
            .position(|item| {
                item.collection == collection
                    && item
                        .binding
                        .as_ref()
                        .is_some_and(|binding| binding.handle == handle)
            })
            .expect("a bound handle")
    }

    /// The `seq` and body of the card a handle binds in `collection`.
    fn bound_card(&self, collection: &str, handle: &str) -> (i64, ObjectName) {
        let item = &self.items[self.bound_index(collection, handle)];
        (item.seq, item.object.clone().expect("a held body"))
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

    use rusqlite::types::Value;

    use crate::{
        engine::{Event, Push},
        history::{History, PAGE, drained},
        model::{Item, Model, State},
        oracle,
        queue::RowState,
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
        let histories = [history(), History::cards(13)];
        for (index, step) in histories
            .iter()
            .flat_map(|history| history.steps.iter())
            .enumerate()
        {
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

        let kinds: Vec<&str> = run.pushes.iter().map(|(push, _)| push.name()).collect();
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

    fn card(model: &Model, handle: &str) -> Item {
        model
            .items
            .iter()
            .find(|item| {
                item.binding
                    .as_ref()
                    .is_some_and(|binding| binding.handle == handle)
            })
            .cloned()
            .unwrap()
    }

    #[test]
    fn a_dav_round_names_every_member_with_the_body_it_carries() {
        let history = History::cards(13);
        let step = &history.steps[1];
        let run = step.run.as_ref().unwrap();
        assert!(
            run.pages
                .iter()
                .flat_map(|page| &page.items)
                .all(|member| member.carries)
        );
        assert_eq!(run.events.len(), 5);
        for item in &step.model.items {
            let binding = item.binding.as_ref().unwrap();
            assert_eq!(item.level, 2);
            assert_eq!(binding.base_object, item.object);
            assert!(binding.base_revision.is_some());
        }
    }

    #[test]
    fn a_server_edit_is_pulled_and_a_local_one_pushed_on_its_revision() {
        let history = History::cards(13);
        let before = &history.steps[2].model;
        let step = &history.steps[3];
        let run = step.run.as_ref().unwrap();

        assert!(
            run.events
                .contains(&Event::ContentChanged(String::from("r1.vcf")))
        );
        let pulled = card(&step.model, "r1.vcf");
        assert_eq!(
            pulled.summary.get("fn"),
            Value::Text(String::from("Edited On The Server"))
        );
        assert_eq!(pulled.binding.as_ref().unwrap().base_object, pulled.object);
        assert_eq!(
            pulled.sort_key, "edited on the server",
            "a pull restates the sort key"
        );

        assert_eq!(run.pushes.len(), 1);
        let Push::Update {
            handle,
            if_match,
            object,
        } = &run.pushes[0].0
        else {
            panic!("an update");
        };
        assert_eq!(handle, "r2.vcf");
        assert_eq!(
            if_match,
            &card(before, "r2.vcf").binding.unwrap().base_revision
        );
        let pushed = card(&step.model, "r2.vcf");
        let binding = pushed.binding.as_ref().unwrap();
        assert_eq!(binding.base_object.as_ref(), Some(object));
        assert_eq!(binding.base_revision, run.outcomes[0].revision);
        assert!(run.outcomes[0].revision.is_some());
    }

    #[test]
    fn an_edit_on_both_sides_is_recorded_in_conflict_and_pushes_nothing() {
        let history = History::cards(13);
        let step = &history.steps[5];
        let run = step.run.as_ref().unwrap();
        assert_eq!(run.events, [Event::Conflicted(String::from("r3.vcf"))]);
        assert!(run.pushes.is_empty());

        let item = card(&step.model, "r3.vcf");
        let binding = item.binding.as_ref().unwrap();
        assert!(binding.conflicted);
        assert!(binding.conflict_object.is_some() && binding.conflict_revision.is_some());
        assert_eq!(
            item.summary.get("fn"),
            Value::Text(String::from("Our Version"))
        );
        assert_ne!(binding.base_object, item.object);
    }

    #[test]
    fn a_resolution_pushes_on_the_revision_it_resolved_and_deletes_travel_both_ways() {
        let history = History::cards(13);
        let resolved = &history.steps[6].model;
        assert!(drained(resolved));
        assert!(
            resolved
                .queue
                .iter()
                .all(|row| matches!(row.state, RowState::Applied(_)))
        );
        let conflicted = card(&history.steps[5].model, "r3.vcf").binding.unwrap();
        let settled = card(resolved, "r3.vcf").binding.unwrap();
        assert!(!settled.conflicted);
        assert_eq!(settled.base_revision, conflicted.conflict_revision);
        assert_eq!(settled.base_object, conflicted.conflict_object);

        let step = &history.steps[7];
        let run = step.run.as_ref().unwrap();
        let names: Vec<&str> = run.pushes.iter().map(|(push, _)| push.name()).collect();
        assert_eq!(names, ["update", "remove"]);
        let Push::Update { if_match, .. } = &run.pushes[0].0 else {
            panic!("an update");
        };
        assert_eq!(if_match, &conflicted.conflict_revision);
        let Push::Remove { if_match, .. } = &run.pushes[1].0 else {
            panic!("a remove");
        };
        assert!(if_match.is_some());
        assert!(
            run.events
                .contains(&Event::Vanished(String::from("r5.vcf")))
        );

        let retained = step
            .model
            .items
            .iter()
            .filter(|item| matches!(item.state, State::Retained { .. }))
            .count();
        assert_eq!(retained, 2);
        assert!(history.steps[8].run.as_ref().unwrap().pushes.is_empty());
        assert!(history.steps[8].run.as_ref().unwrap().events.is_empty());
    }
}
