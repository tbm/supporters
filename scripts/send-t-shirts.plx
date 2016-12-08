#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);
use DBI;
use Encode qw(encode decode);

use Supporters;

my $LEDGER_CMD = "/usr/local/bin/ledger";

if (@ARGV != 4 and @ARGV != 5) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <WHO> <HOW> <SUPPORTER_CHECKLIST_TEX_FILE> <VERBOSITY_LEVEL>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $WHO, $HOW, $TEX_FILE, $VERBOSE) = @ARGV;
$VERBOSE = 0 if not defined $VERBOSE;

my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, [ "none" ]);

my %idsSent;
open(TEX_FILE, "<", $TEX_FILE);

while (my $line = <TEX_FILE>) {
  if ($line =~ /Box.*\&\s*(\d+)\s*\&\s*(\S+)\s*\&\s*(\S+)\s*\&/) {
    my($id, $ledgerEntityId, $size) = ($1, $2, $3);
    die "id $id, and/or size $size not defined" unless defined $id and defined $size;
    $idsSent{$id} = $size;
  } else {
    print STDERR "skipping line $line" if ($VERBOSE >= 2);
  }
}

close TEX_FILE;

foreach my $id (sort keys %idsSent) {
  my $request;
  my @requestTypes = $sp->getRequestType();
  foreach my $type (@requestTypes) {
    next unless if ($type =~ /t-shirt/);
    $request = $sp->getRequest({ donorId => $id, requestType => $type,
                                 ignoreHeldRequests => 1, ignoreFulfilledRequests => 1 });
    if (defined $request and defined $request->{requestType}) {
      if ($request->{requestConfiguration} ne $idsSent{$id}) {
        my $out = "WARNING: not fufilling $id request for $request->{requstConfiguration} because we sent wrong size of $idsSent{$id}!\n";
        print $out;
        print STDERR $out;
        $request = undef;
      }
    }
    last if defined $request;
  }
  if (not defined $request) {
    my $out = "WARNING: We seem to have sent $id an $idsSent{$id} t-shirt that $id didn't request!  Ignoring that and contuining...\n";
    print $out;
    print STDERR $out;
    next;
  }
  $sp->fulfillRequest({ donorId => $id, requestType => $request->{requestType},
                      who => $WHO, how => $HOW});

  my $emailTo = $sp->getPreferredEmailAddress($id);
  if (not defined $emailTo) {
    my(@addr) = $sp->getEmailAddresses($id);
    $emailTo = $addr[0];
  }
  my $fromAddress = 'info@sfconservancy.org';
  my $pingNoGet = "";
  $pingNoGet = "\nPlease ping us if you do not receive your t-shirt within two weeks in the\nUSA, or three weeks outside of the USA.\n\n"
  if ($HOW =~ /post/);

  open(SENDMAIL, "|/usr/lib/sendmail -f \"$fromAddress\" -oi -oem -- $emailTo $fromAddress") or
      die "unable to run sendmail: $!";
  print SENDMAIL <<DATA;
To: $emailTo
From: "Software Freedom Conservancy" <$fromAddress>
Subject: $idsSent{$id} Conservancy T-Shirt was $HOW

According to our records, the t-shirt of size $idsSent{$id} that you
requested as a Conservancy Supporter was $HOW.
$pingNoGet

Thank you again so much for supporting Conservancy.  When we placed our order
for these t-shirts, our shirt supplier (which is itself a 501c3 dedicated to
educating high school kids in New York) sent us the wrong color t-shirt
before appropriately filling the order in a deep gray. We decided to give you
a second shirt in this fun color as an extra thank you for being a Supporter.

The two shirts now feel like a symbol for where we are in our Supporter
program - if each of our Supporters just got a single friend to sign up, we'd
achieve sustainability for all of Conservancy's programs.

We'd really appreciate if you'd post pictures of the shirt on social media
and encourage others to sign up as a Conservancy supporter at
https://sfconservancy.org/supporter/ .

Sincerely,
-- 
Karen M. Sandler, Executive Director, Software Freedom Conservancy
    and
Bradley M. Kuhn, Distinguished Technologist, Software Freedom Conservancy
DATA
  close SENDMAIL;
  die "Unable to send email to $id: $!" unless $? == 0;

  print STDERR "Emailed $emailTo for $id sending of $request->{requestConfiguration} size t-shirt and marked it fulfilled in database\n" if ($VERBOSE);
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c send-t-shirts.plx"
# End:

