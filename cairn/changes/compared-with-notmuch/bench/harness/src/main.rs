//! pimdir side of the notmuch comparison: a Maildir connector driving
//! io-pimdir's sync engine, the index refresh, and in-process query timing.
//!
//! ```sh
//! pimbench sync  STORE MAILDIR_ROOT STATE_DIR [PAGE]
//! pimbench index STORE
//! pimbench query STORE REPEATS QUERY...
//! ```

use std::{
    collections::{BTreeMap, BTreeSet},
    env, fs, io,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

use io_pimdir::{
    change::PimdirChange,
    client::{
        PimdirStore,
        search::{PimdirIndex, PimdirIndexRefreshOptions, PimdirSearchOptions},
    },
    collection::{PimdirCheckpoint, PimdirCollectionId, PimdirCursor},
    hash,
    placement::{PimdirFlags, PimdirHandle},
    remote::{
        PimdirEnumerate, PimdirEnumerated, PimdirFetchedBody, PimdirFetchedItem, PimdirListing,
        PimdirPushOutcome, PimdirPushResult, PimdirRemote, PimdirRemoteItem, PimdirRemoteMeta,
        PimdirRemoteSnapshot, PimdirTier,
    },
    search::query::PimdirQuery,
    summary,
    sync::PimdirSyncOptions,
};

/// One message file of a Maildir folder.
#[derive(Clone)]
struct Entry {
    handle: String,
    name: String,
    path: PathBuf,
}

/// A Maildir as a pimdir source: handles are the unique part of the file
/// name, flags its info suffix, every listed member carries its body.
struct Maildir {
    root: PathBuf,
    state: PathBuf,
    page: usize,
    listings: BTreeMap<String, Vec<Entry>>,
    read_bytes: u64,
}

fn handle_of(name: &str) -> &str {
    name.split(':').next().unwrap_or(name)
}

fn flags_of(name: &str) -> PimdirFlags {
    let mut flags = BTreeSet::new();
    if let Some((_, info)) = name.split_once(":2,") {
        for c in info.chars() {
            let flag = match c {
                'S' => "\\Seen",
                'F' => "\\Flagged",
                'R' => "\\Answered",
                'D' => "\\Draft",
                _ => continue,
            };
            flags.insert(flag.to_string());
        }
    }
    PimdirFlags::Known(flags)
}

impl Maildir {
    fn list(&self, collection: &str) -> io::Result<Vec<Entry>> {
        let mut entries = Vec::new();
        for sub in ["cur", "new"] {
            let dir = self.root.join(collection).join(sub);
            let Ok(read) = fs::read_dir(&dir) else {
                continue;
            };
            for entry in read {
                let entry = entry?;
                let name = entry.file_name().to_string_lossy().into_owned();
                if name.starts_with('.') {
                    continue;
                }
                entries.push(Entry {
                    handle: handle_of(&name).to_string(),
                    path: entry.path(),
                    name,
                });
            }
        }
        entries.sort_by(|a, b| a.handle.cmp(&b.handle));
        entries.dedup_by(|a, b| a.handle == b.handle);
        Ok(entries)
    }

    fn sidecar(&self, collection: &str) -> PathBuf {
        self.state.join(collection.replace('/', "%"))
    }

    fn save_names(&self, collection: &str, entries: &[Entry]) -> io::Result<()> {
        let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
        fs::write(self.sidecar(collection), names.join("\n"))
    }

    fn load_names(&self, collection: &str) -> io::Result<BTreeMap<String, String>> {
        let text = fs::read_to_string(self.sidecar(collection)).unwrap_or_default();
        Ok(text
            .lines()
            .filter(|l| !l.is_empty())
            .map(|l| (handle_of(l).to_string(), l.to_string()))
            .collect())
    }

    fn item(&mut self, entry: &Entry) -> io::Result<PimdirRemoteItem> {
        let bytes = fs::read(&entry.path)?;
        self.read_bytes += bytes.len() as u64;
        let derivation = summary::mail::derive(&bytes);
        let body = PimdirFetchedBody::Inline {
            hash: hash::hash(&bytes),
            bytes,
        };
        Ok(PimdirRemoteItem {
            handle: PimdirHandle(entry.handle.clone()),
            flags: flags_of(&entry.name),
            revision: None,
            meta: PimdirRemoteMeta::new(derivation).with_body(body),
        })
    }
}

impl PimdirRemote for Maildir {
    type Error = io::Error;

    fn enumerate(
        &mut self,
        collection: &PimdirCollectionId,
        request: PimdirEnumerate,
    ) -> Result<PimdirEnumerated, io::Error> {
        let name = collection.0.clone();
        match request.listing {
            PimdirListing::Round { cursor, .. } => {
                let start = match &cursor {
                    None => {
                        let listing = self.list(&name)?;
                        self.listings.insert(name.clone(), listing);
                        0
                    }
                    Some(PimdirCursor(bytes)) => {
                        if !self.listings.contains_key(&name) {
                            let listing = self.list(&name)?;
                            self.listings.insert(name.clone(), listing);
                        }
                        String::from_utf8_lossy(bytes).parse().unwrap_or(0)
                    }
                };
                let listing = self.listings[&name].clone();
                let end = (start + self.page).min(listing.len());
                let mut items = Vec::with_capacity(end - start);
                for entry in &listing[start..end] {
                    items.push(self.item(entry)?);
                }
                let (cursor, checkpoint) = match end < listing.len() {
                    true => (Some(PimdirCursor(end.to_string().into_bytes())), None),
                    false => {
                        self.save_names(&name, &listing)?;
                        (None, Some(PimdirCheckpoint(b"1".to_vec())))
                    }
                };
                Ok(PimdirRemoteSnapshot::page(items, cursor, checkpoint).into())
            }
            PimdirListing::Delta(PimdirCheckpoint(old)) => {
                let known = self.load_names(&name)?;
                let listing = self.list(&name)?;
                let mut items = Vec::new();
                let mut present = BTreeSet::new();
                for entry in &listing {
                    present.insert(entry.handle.clone());
                    if known.get(&entry.handle) != Some(&entry.name) {
                        items.push(self.item(entry)?);
                    }
                }
                let vanished = known
                    .keys()
                    .filter(|h| !present.contains(*h))
                    .map(|h| PimdirHandle(h.clone()))
                    .collect();
                self.save_names(&name, &listing)?;
                let next: u64 = String::from_utf8_lossy(&old).parse().unwrap_or(0) + 1;
                self.listings.insert(name, listing);
                Ok(PimdirRemoteSnapshot::delta(
                    items,
                    vanished,
                    PimdirCheckpoint(next.to_string().into_bytes()),
                )
                .into())
            }
            PimdirListing::Head(_) => Ok(PimdirEnumerated::NoHead),
        }
    }

    fn fetch(
        &mut self,
        collection: &PimdirCollectionId,
        handles: Vec<PimdirHandle>,
        tier: PimdirTier,
    ) -> Result<Vec<PimdirFetchedItem>, io::Error> {
        let name = collection.0.clone();
        if !self.listings.contains_key(&name) {
            let listing = self.list(&name)?;
            self.listings.insert(name.clone(), listing);
        }
        let by_handle: BTreeMap<String, Entry> = self.listings[&name]
            .iter()
            .map(|e| (e.handle.clone(), e.clone()))
            .collect();
        let mut out = Vec::new();
        for handle in handles {
            let Some(entry) = by_handle.get(&handle.0) else {
                continue;
            };
            let bytes = fs::read(&entry.path)?;
            self.read_bytes += bytes.len() as u64;
            let d = summary::mail::derive(&bytes);
            let body = match tier {
                PimdirTier::Full => Some(PimdirFetchedBody::Inline {
                    hash: hash::hash(&bytes),
                    bytes,
                }),
                PimdirTier::Meta => None,
            };
            out.push(PimdirFetchedItem {
                handle,
                link_id: d.link_id,
                summary: d.summary,
                sort_key: d.sort_key,
                body,
                revision: None,
            });
        }
        Ok(out)
    }

    fn push(
        &mut self,
        _collection: &PimdirCollectionId,
        changes: Vec<PimdirChange>,
    ) -> Result<Vec<PimdirPushResult>, io::Error> {
        Ok(changes
            .iter()
            .map(|change| PimdirPushResult {
                handle: change.handle().clone(),
                outcome: PimdirPushOutcome::Accepted,
                assigned: None,
                revision: None,
                relocated: false,
            })
            .collect())
    }
}

/// Every Maildir folder under `root`, as paths relative to it.
fn folders(root: &Path) -> io::Result<Vec<String>> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        if dir.join("cur").is_dir() {
            let rel = dir.strip_prefix(root).unwrap().to_string_lossy().into_owned();
            out.push(rel);
        }
        for entry in fs::read_dir(&dir)? {
            let entry = entry?;
            let name = entry.file_name();
            if matches!(name.to_str(), Some("cur" | "new" | "tmp")) {
                continue;
            }
            if entry.file_type()?.is_dir() {
                stack.push(entry.path());
            }
        }
    }
    out.sort();
    Ok(out)
}

fn peak_rss_kib() -> u64 {
    fs::read_to_string("/proc/self/status")
        .unwrap_or_default()
        .lines()
        .find_map(|l| l.strip_prefix("VmHWM:"))
        .and_then(|v| v.trim().trim_end_matches(" kB").trim().parse().ok())
        .unwrap_or(0)
}

fn cmd_sync(args: &[String]) {
    let store_dir = PathBuf::from(&args[0]);
    let root = PathBuf::from(&args[1]);
    let state = PathBuf::from(&args[2]);
    let page = args.get(3).and_then(|p| p.parse().ok()).unwrap_or(1000);
    fs::create_dir_all(&state).unwrap();
    let folders = folders(&root).unwrap();
    let mut store = PimdirStore::open(&store_dir).unwrap().for_source("maildir");
    let mut remote = Maildir {
        root,
        state,
        page,
        listings: BTreeMap::new(),
        read_bytes: 0,
    };
    let at = Instant::now();
    let (mut pulled, mut unreadable) = (0, 0);
    for folder in &folders {
        store.ensure_collection(folder, "message/rfc822").unwrap();
        let report = store
            .sync(
                PimdirCollectionId(folder.clone()),
                PimdirSyncOptions::default(),
                &mut remote,
            )
            .unwrap_or_else(|err| panic!("{folder}: {err:?}"));
        pulled += report.pulled;
        unreadable += report.unreadable;
        remote.listings.remove(folder);
    }
    let elapsed = at.elapsed();
    println!(
        "sync folders={} pulled={pulled} unreadable={unreadable} read_mib={:.1} secs={:.2} peak_rss_mib={:.0}",
        folders.len(),
        remote.read_bytes as f64 / 1048576.0,
        elapsed.as_secs_f64(),
        peak_rss_kib() as f64 / 1024.0,
    );
}

fn cmd_index(args: &[String]) {
    let store_dir = PathBuf::from(&args[0]);
    let at = Instant::now();
    let report = PimdirIndex::open(&store_dir)
        .unwrap()
        .refresh(&PimdirIndexRefreshOptions::default())
        .unwrap();
    println!(
        "index folded={} indexed={} secs={:.2} peak_rss_mib={:.0}",
        report.folded,
        report.indexed,
        at.elapsed().as_secs_f64(),
        peak_rss_kib() as f64 / 1024.0,
    );
}

fn median(times: &mut [Duration]) -> f64 {
    times.sort();
    times[times.len() / 2].as_secs_f64() * 1000.0
}

fn cmd_query(args: &[String]) {
    let store_dir = PathBuf::from(&args[0]);
    let repeats: usize = args[1].parse().unwrap();
    let index = PimdirIndex::open_query(&store_dir).unwrap();
    let options = PimdirSearchOptions::default();
    for raw in &args[2..] {
        let query = match PimdirQuery::parse(raw) {
            Ok(query) => query,
            Err(err) => {
                println!("query {raw:?} refused: {err:?}");
                continue;
            }
        };
        let (mut page_t, mut count_t) = (Vec::new(), Vec::new());
        let (mut hits, mut count) = (0, 0);
        for _ in 0..repeats {
            let at = Instant::now();
            hits = index.search(&query, &options).unwrap().hits.len();
            page_t.push(at.elapsed());
            let at = Instant::now();
            count = index.count(&query, &options.clock).unwrap().count;
            count_t.push(at.elapsed());
        }
        println!(
            "query {raw:?} count={count} count_ms={:.1} page={hits} page_ms={:.1}",
            median(&mut count_t),
            median(&mut page_t),
        );
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("sync") => cmd_sync(&args[1..]),
        Some("index") => cmd_index(&args[1..]),
        Some("query") => cmd_query(&args[1..]),
        _ => eprintln!("usage: pimbench sync|index|query ..."),
    }
}
