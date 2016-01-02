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
  foreach my $type (qw/t-shirt-0 t-shirt-1/) {
    $request = $sp->getRequest({ donorId => $id, requestType => 't-shirt-0', ignoreFulfilledRequests => 1 });
    if (defined $request and defined $request->{requestType}) {
      if ($request->{requestConfiguration} ne $idsSent{$id}) {
        my $out = "WARNING: not fufilling $id request for $request->{requstConfiguration} because we sent wrong size of $idsSent{$id}!\n";
        print $out;
        print STDERR $out;
        $request = undef;
      }
    }
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
  open(SENDMAIL, "|/usr/lib/sendmail -f \"$fromAddress\" -oi -oem -- $emailTo") or
      die "unable to run sendmail: $!";
  print SENDMAIL <<DATA;
To: $emailTo
From: "Software Freedom Conservancy" <$fromAddress>
Subject: $idsSent{$id} Conservancy T-Shirt sent via post.

The t-shirt of size $idsSent{$id} that you requested as a Conservancy
Supporter was sent to you via the post today.  Please ping us if you don't
receive your shirt within two weeks.

Thank you again so much for supporting Conservancy.  When your shirt arrives,
we'd really appreciate if you'd post pictures of the shirt on social media
and encourage others to sign up as a Conservancy supporter at
https://sfconservancy.org/supporter/ .


Sincerely,
-- 
Bradley M. Kuhn
Distinguished Technologist, Software Freedom Conservancy
DATA
  close SENDMAIL;
  die "Unable to send email to $id: $!" unless $? == 0;
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c send-t-shirts.plx"
# End:

