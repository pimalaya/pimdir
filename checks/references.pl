#!/usr/bin/env perl
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# Checks the references of every markdown file outside cairn/ under the
# directory given (the repository by default): each relative link names a file
# or directory that exists, and an anchor a heading of the markdown file it
# points into, slugged as GitHub slugs it; each section reference names a
# numbered heading of its document. A section reference is `§n` or `Annex X`,
# of the document named right before it (STORAGE, SYNC, SEARCH, GUIDE,
# OVERVIEW, with `.md` or not, AGENTS.md or gtd.md, as a name or a link), else
# of the reference it continues in a list (`STORAGE §2, §5 and §12`), else of
# the file itself, as each part's conventions say; an annex is STORAGE's
# wherever it is cited, and one after another markdown file, an RFC, a BCP, an
# ISO standard or Unicode is outside the repository. Needs perl alone.
use strict;
use warnings;
use utf8;
use File::Basename qw(dirname);
use File::Find qw(find);
use File::Spec;

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $root = shift // '.';
my %documents = (STORAGE => 'STORAGE.md', SYNC => 'SYNC.md', SEARCH => 'SEARCH.md',
                 GUIDE => 'GUIDE.md', OVERVIEW => 'OVERVIEW.md');
my %own = (reverse(%documents), 'AGENTS.md' => 'AGENTS', 'conventions/gtd.md' => 'GTD');
my %file_of = (%documents, AGENTS => 'AGENTS.md', GTD => 'conventions/gtd.md');
my %by_name = ((map { $_ => $_ } keys %documents), AGENTS => 'AGENTS', gtd => 'GTD');

my @files;
find({ no_chdir => 1, wanted => sub {
    my $relative = File::Spec->abs2rel($File::Find::name, $root);
    if (-d $_ && $relative =~ m{^(cairn|\.git)$}) {
        $File::Find::prune = 1;
    } elsif (-f $_ && /\.md$/) {
        push @files, $relative;
    }
} }, $root);
@files = sort @files;

# The lines of a file outside fenced code blocks, inline code removed, each
# with its number.
sub prose {
    my ($file) = @_;
    open my $fh, '<:encoding(UTF-8)', "$root/$file" or die "$file: $!";
    my ($fence, @lines) = (0);
    while (my $line = <$fh>) {
        if ($line =~ /^\s*(```|~~~)/) { $fence = !$fence; next }
        next if $fence;
        (my $text = $line) =~ s/`[^`]*`//g;
        push @lines, [$., $text];
    }
    return @lines;
}

# The headings of a markdown file as GitHub slugs them, and its numbered
# sections (`## 4.`, `### 4.2`, `### A.1`, `## Annex A.`).
my (%slugs, %sections);
sub headings {
    my ($file) = @_;
    return if $slugs{$file};
    my (%seen, %set, %numbered);
    open my $fh, '<:encoding(UTF-8)', "$root/$file" or return;
    my $fence = 0;
    while (my $line = <$fh>) {
        if ($line =~ /^\s*(```|~~~)/) { $fence = !$fence; next }
        next if $fence || $line !~ /^#{1,6}\s+(.*?)\s*#*\s*$/;
        my $title = $1;
        $numbered{$1} = 1 if $title =~ /^(?:Annex\s+)?([0-9]+(?:\.[0-9]+)*|[A-Z](?:\.[0-9]+)*)\.?\s/;
        my $slug = lc $title;
        $slug =~ s/\[([^\]]*)\]\([^)]*\)/$1/g;
        $slug =~ s/[^\p{L}\p{N}\p{M}\s_-]//g;
        $slug =~ s/\s/-/g;
        my $unique = exists $seen{$slug} ? "$slug-" . ++$seen{$slug} : $slug;
        $seen{$slug} //= 0;
        $set{$unique} = 1;
    }
    $slugs{$file} = \%set;
    $sections{$file} = \%numbered;
}

my ($links, $references, $broken) = (0, 0, 0);
for my $file (@files) {
    for (prose($file)) {
        my ($number, $text) = @$_;

        while ($text =~ /\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)/g) {
            my $target = $1;
            next if $target =~ m{^(?:[a-z][a-z0-9+.-]*:|//)}i;
            $links++;
            my ($path, $anchor) = split /#/, $target, 2;
            my $destination = $path eq '' ? $file : File::Spec->canonpath(dirname($file) . "/$path");
            if ($path ne '' && !-e "$root/$destination") {
                print STDERR "$file:$number: a link to $target, which does not exist\n";
                $broken++;
            } elsif (defined $anchor && $anchor ne '' && $destination =~ /\.md$/) {
                headings($destination);
                if (!$slugs{$destination}{lc $anchor}) {
                    print STDERR "$file:$number: a link to $target, whose anchor names no heading\n";
                    $broken++;
                }
            }
        }

        my ($last_end, $last_document) = (-1, undef);
        while ($text =~ /(?:\b(STORAGE|SYNC|SEARCH|GUIDE|OVERVIEW)(?:\.md)?\s+)?(§|Annex\s+)([0-9]+(?:\.[0-9]+)*|[A-Z](?:\.[0-9]+)*)\b/g) {
            my ($named, $sign, $section, $start, $end) = ($1, $2, $3, $-[0], $+[0]);
            my $before = substr($text, 0, $start);
            my $document;
            if (defined $named) {
                $document = $named;
            } elsif ($before =~ /\b([\w-]+)\.md\)?\s*$/) {
                $document = $by_name{$1} // 'outside';
            } elsif ($before =~ /(?:\b(?:RFC|BCP|ISO)\s*[0-9]+|\bUnicode)\s*$/) {
                $document = 'outside';
            } elsif ($last_end >= 0 && substr($text, $last_end, $start - $last_end) =~ /^(?:,\s*|\s+(?:and|or|to)\s+|,\s+and\s+)$/) {
                $document = $last_document;
            } elsif ($sign =~ /^Annex/) {
                $document = 'STORAGE';
            } else {
                $document = $own{$file};
            }
            ($last_end, $last_document) = ($end, $document);
            next if defined $document && $document eq 'outside';
            $references++;
            if (!defined $document) {
                print STDERR "$file:$number: §$section names no document, the file numbering no section\n";
                $broken++;
                next;
            }
            headings($file_of{$document});
            if (!$sections{$file_of{$document}}{$section}) {
                print STDERR "$file:$number: $document §$section, a section $file_of{$document} does not number\n";
                $broken++;
            }
        }
    }
}

if ($broken) {
    print STDERR "$broken reference(s) broken\n";
    exit 1;
}
print scalar(@files) . " markdown files, $links relative links and $references section references resolve\n";
