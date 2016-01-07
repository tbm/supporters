#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close chdir);
use DBI;
use Encode qw(encode decode);

use LaTeX::Encode;

use Supporters;

my $LEDGER_CMD = "/usr/local/bin/ledger";

if (@ARGV != 3 and @ARGV != 4) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <SIZE_COUNTS> <OUTPUT_DIRECTORY> <VERBOSE>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $SIZE_COUNTS, $OUTPUT_DIRECTORY, $VERBOSE) = @ARGV;
$VERBOSE = 0 if not defined $VERBOSE;

open(SIZE_COUNTS, "<", $SIZE_COUNTS);

my %sizeCounts;
while (my $line = <SIZE_COUNTS>) {
  if ($line =~ /^\s*(\S+)\s+(\d+)\s*/) {
    my($size, $count) = ($1, $2, $3);
    $sizeCounts{$size} = $count;
  } else {
    die "invalid line $line in $SIZE_COUNTS file";
  }
}
close SIZE_COUNTS;

open(LIST, ">checklist-ready-to-send.tex") or die "unable to open list: $!";
open(LABELS, ">labels-ready-to-send.tex") or die "unable to open labels: $!";

print LIST <<LIST_HEADER
\\documentclass[letterpaper, 10pt]{letter}
\\usepackage{units}
\\usepackage{color}
\\usepackage{wasysym}
\\usepackage{latexsym}
\\usepackage{amsfonts}
\\usepackage{amssymb}
\\begin{document}
\\vspace{-15in}

\\begin{tabular}{|l|l|l|l|l|} \\hline
LIST_HEADER
;


my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, [ "none" ]);


my(@supporterIds) = $sp->findDonor({});

my $overallCount = 0;
my %lines;

foreach my $id (@supporterIds) {
  my $sizeNeeded;
  foreach my $type (qw/t-shirt-0 t-shirt-1/) {
    my $request = $sp->getRequest({ donorId => $id, requestType => 't-shirt-0', ignoreFulfilledRequests => 1 });
    if (defined $request and defined $request->{requestType}) {
      $sizeNeeded = $request->{requestConfiguration};
      last;
    }
  }
  next if not defined $sizeNeeded;   # If we don't need a size, we don't have a request.
  my(@postalAddresses) = $sp->getPostalAddresses($id);
  my $latexPostal = latex_encode($postalAddresses[0]);
  if ($latexPostal =~ /unmatched/) {
    print "Skipping $id request for $sizeNeeded because the address has characters the post office will not accept\n" if $VERBOSE;
    next;
  }

  { no strict;  no warnings; $sizeCounts{$sizeNeeded}--; }
  if ($sizeCounts{$sizeNeeded} < 0) {
    print STDERR "Skipping $id request for $sizeNeeded because we are out.\n" if $VERBOSE;
    next;
  }
  $overallCount++;
  $lines{$sizeNeeded}{labels} = "" unless defined $lines{$sizeNeeded}{labels};
  $lines{$sizeNeeded}{checklist} = [] unless defined $lines{$sizeNeeded}{checklist};
  $lines{$sizeNeeded}{labels} .= '\mlabel{}{TO: \\\\ ' . join(' \\\\ ', split('\n', $latexPostal)) . "}\n";
  my $shortLatexPostal = latex_encode(sprintf('%-30.30s', join(" ", reverse split('\n', $postalAddresses[0]))));
  push(@{$lines{$sizeNeeded}{checklst}}, '{ $\Box$} &' . sprintf("%-3d  & %5s & %-30s  & %s ",
                                                  $id, encode('UTF-8', $sp->getLedgerEntityId($id)),
                                                  encode('UTF-8', $sizeNeeded),
                                                  $shortLatexPostal) .
                                                    '\\\\ \hline' . "\n");
}
my $lineCount = 0;
foreach my $size (sort { $a cmp $b } keys %lines) {
  foreach my $line (@{$lines{$size}{boxes}}) {
    if ($lineCount++ > 40) {
      $lineCount = 0;
      print LIST "\n\n", '\end{tabular}',"\n\\pagebreak\n\\begin{tabular}{|l|l|l|l|l|} \\hline\n";
    }
    print LIST $line;
  }
  print LABELS $lines{$size}{labels};
  delete $lines{$size}{labels};
}
die "error: parallel hashes had different keys?" unless scalar(keys %{$lines{$size}{labels}}) <= 0;

print LIST "\n\n", '\end{tabular}',"\n";
print LIST "FINAL INVENTORY EXPECTED\n\\begin{tabular}{|l|l|} \\hline\n";
print STDERR "Total Shirts: $overallCount\n" if $VERBOSE;

my %needList;
foreach my $size (sort keys %sizeCounts) {
  if ($sizeCounts{$size} < 0) {
    $needList{$size} = abs($sizeCounts{$size});
    $sizeCounts{$size} = 0;
  }
  print LIST "$size & $sizeCounts{$size}\\\\\n";
}
if (scalar(keys %needList) > 0) {
  print LIST "\\hline \n\n", '\end{tabular}',"\n\n\\bigskip\n\n";
  print LIST "T-SHIRTS NEEDED\n\\begin{tabular}{|l|l|} \\hline\n";
  foreach my $size (sort keys %needList) {
    print LIST "$size & $needList{$size}\\\\\n";
  }
}
print LIST "\\hline \n\n", '\end{tabular}',"\n\n\nOVERALL SENDING COUNT: $overallCount", '\end{document}', "\n";
close LIST;
close LABELS;

###############################################################################
#
# Local variables:
# compile-command: "perl -c send-t-shirts.plx"
# End:
