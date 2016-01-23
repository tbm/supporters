#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);

use DBI;
use Encode qw(encode decode);
use Date::Manip::DM5;
use Supporters;

my $TODAY = UnixDate(ParseDate("today"), '%Y-%m-%d');

if (@ARGV < 7 ) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <REQUEST_NAME> <FROM_ADDRESS> <EMAIL_TEMPLATE> <MONTHLY_SEARCH_REGEX> <ANNUAL_SEARCH_REGEX>  <VERBOSE> <LEDGER_CMD_LINE>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $REQUEST_NAME, $FROM_ADDRESS, $EMAIL_TEMPLATE, $MONTHLY_SEARCH_REGEX, $ANNUAL_SEARCH_REGEX, $VERBOSE,
   @LEDGER_CMN_LINE) = @ARGV;


my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, \@LEDGER_CMN_LINE, { monthly => $MONTHLY_SEARCH_REGEX, annual => $ANNUAL_SEARCH_REGEX});

my(@supporterIds) = $sp->findDonor({});

foreach my $supporterId (@supporterIds) {
  my $expiresOn = $sp->supporterExpirationDate($supporterId);
  my $isLapsed = ( (not defined $expiresOn) or $expiresOn lt $TODAY);

  my $request = $sp->getRequest({ donorId => $supporterId, requestType => $REQUEST_NAME});

  if (defined $request) {
    if (defined $request->{fulfillDate}) {
      print STDERR "$supporterId lapsed on $expiresOn but recorded as renewed on $request->{fulfillDate}\n"
        if ($isLapsed and $VERBOSE);
    } elsif (not $isLapsed) {
      $sp->fulfillRequest({donorId => $supporterId, requestType => $REQUEST_NAME,
                           who => $supporterId, how => "apparent renewal not noticed during import"});
      print STDERR "$supporterId now expires on $expiresOn, recording rewnewal of type $REQUEST_NAME\n"
        if $VERBOSE;
    } else {
      print STDERR "$supporterId received this renewal notice already on $request->{requestDate}\n"
        if $VERBOSE;
    }
    next;
  }
  print STDERR "$supporterId skipped since he is not lapsed\n" if ( (not $isLapsed) and $VERBOSE > 1);
  next if not $isLapsed;

  my %emails;
  my $email = $sp->getPreferredEmailAddress($supporterId);
  if (defined $email) {
    $emails{$email} = {};
  } else {
    %emails = $sp->getEmailAddresses($supporterId);
  }
  my $lastDonateDate = $sp->donorLastGave($supporterId);

  open(MESSAGE, "<", $EMAIL_TEMPLATE);
  my @message;
  while (my $line = <MESSAGE> ) {
    $line =~ s/FIXME_LAST_DONATE_DATE/$lastDonateDate/g;
    push(@message, $line);
  }
  close MESSAGE;
  my $emailTo = join(' ', keys %emails);
  open(SENDMAIL, "|/usr/lib/sendmail -f \"$FROM_ADDRESS\" -oi -oem -- $emailTo $FROM_ADDRESS") or
    die "unable to run sendmail: $!";

  print STDERR "Sending to $supporterId at $emailTo\n";
  print SENDMAIL "To: ", join(', ', keys %emails), "\n";
  print SENDMAIL @message;

  close SENDMAIL;
  sleep 1;
  $sp->addRequest({donorId => $supporterId, requestType => $REQUEST_NAME});
}
