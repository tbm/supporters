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
    $idsSent{$id}{$size} = 0 if not defined $idsSent{$id}{$size};
    $idsSent{$id}{$size}++;
  } else {
    print STDERR "skipping line $line" if ($VERBOSE >= 2);
  }
}

close TEX_FILE;

foreach my $id (sort keys %idsSent) {
  my @requestTypes = $sp->getRequestType();
  my $sizesSent;
  my $foundRequestCount = 0;
  foreach my $type (@requestTypes) {
    next unless ($type =~ /shirt/);
    my $request = $sp->getRequest({ donorId => $id, requestType => $type,
                                 ignoreHeldRequests => 1, ignoreFulfilledRequests => 1 });
    if (defined $request and defined $request->{requestId} and defined $request->{requestType}) {
      $foundRequestCount++;
      my $size = $request->{requestConfiguration};
      if (not defined $idsSent{$id}{$size} and $idsSent{$id}{$size}-- > 0) {
        my $out = "WARNING: not fufilling $id request for $request->{requstConfiguration} because we sent wrong size of $idsSent{$id}!\n";
        print $out;
        print STDERR $out;
        $request = undef;
      } else {
        $sp->fulfillRequest({ donorId => $id, requestType => $request->{requestType},
                              who => $WHO, how => $HOW});
        if (defined $sizesSent) {
          $sizesSent .= ", $size";
        } else {
          $sizesSent .= "$size";
        }
      }
    }
  }
  unless ($foundRequestCount > 0) {
    my $out = "WARNING: We seem to have sent $id a t-shirt that $id didn't request!  Ignoring that and contuining...\n";
    print $out;
    print STDERR $out;
    next;
  }
  next unless $sp->emailOk($id);
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
Subject: $sizesSent Conservancy T-Shirt was $HOW

According to our records, the t-shirt of size $sizesSent that you
requested as a Conservancy Supporter was $HOW.
$pingNoGet

Thank you again so much for supporting Conservancy.

We'd really appreciate if you'd post pictures of the shirt on social media
and encourage others to sign up as a Conservancy supporter at
https://sfconservancy.org/supporter/ .  As you can see on that page, we are
in the midst of our annual fundraising drive and seeking to reach a match
donation.  There's a unique opportunity until January 15th to give double
support to Conservancy.  Encouraging others to sign up right now will make a
huge difference!

Sincerely,
-- 
Karen M. Sandler, Executive Director, Software Freedom Conservancy
    and
Bradley M. Kuhn, Distinguished Technologist, Software Freedom Conservancy
DATA
  close SENDMAIL;
  die "Unable to send email to $id: $!" unless $? == 0;

  print STDERR "Emailed $emailTo for $id sending of $sizesSent size t-shirt and marked it fulfilled in database\n" if ($VERBOSE);
}
###############################################################################
#
# Local variables:
# compile-command: "perl -c send-t-shirts.plx"
# End:

