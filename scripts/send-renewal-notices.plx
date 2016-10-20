#!/usr/bin/perl

use strict;
use warnings;

use autodie qw(open close);

use DBI;
use Encode qw(encode decode);
use Email::MIME;
use Date::Manip::DM5;
use Supporters;

my $TODAY = UnixDate(ParseDate("today"), '%Y-%m-%d');
my $ONE_WEEK = UnixDate(DateCalc(ParseDate("today"), "+ 1 week"), '%Y-%m-%d');
my $ONE_MONTH = UnixDate(DateCalc(ParseDate("today"), "+ 1 month"), '%Y-%m-%d');
my $TWO_YEARS_AGO = UnixDate(DateCalc(ParseDate("today"), "- 2 years"), '%Y-%m-%d');
my $THREE_YEARS_AGO = UnixDate(DateCalc(ParseDate("today"), "- 3 years"), '%Y-%m-%d');

if (@ARGV < 8 ) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <REQUEST_NAME> <FROM_ADDRESS> <ALL_STAFF_ADDRESS> <EMAIL_TEMPLATE> <MONTHLY_SEARCH_REGEX> <ANNUAL_SEARCH_REGEX>  <VERBOSE> <LEDGER_CMD_LINE>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $REQUEST_NAME, $FROM_ADDRESS, $ALL_STAFF_ADDRESS, $EMAIL_TEMPLATE, $MONTHLY_SEARCH_REGEX, $ANNUAL_SEARCH_REGEX, $VERBOSE,
   @LEDGER_CMN_LINE) = @ARGV;


my $dbh = DBI->connect("dbi:SQLite:dbname=$SUPPORTERS_SQLITE_DB_FILE", "", "",
                               { RaiseError => 1, sqlite_unicode => 1 })
  or die $DBI::errstr;

my $sp = new Supporters($dbh, \@LEDGER_CMN_LINE, { monthly => $MONTHLY_SEARCH_REGEX, annual => $ANNUAL_SEARCH_REGEX});

my(@supporterIds) = $sp->findDonor({});

my %expireReport;
$expireReport{'02-lapsed'}{description} = "Already Lapsed Supporters";
$expireReport{'00-lapsing-this-week'}{description} = "Supporters Lapsing Within a Week";
$expireReport{'01-lapsing-this-month'}{description} = "Supporters Lapsing Within a Month";

my @lapseCategories = ('00-lapsing-this-week', '01-lapsing-this-month', '02-lapsed');
foreach my $cat (@lapseCategories) {
  $expireReport{$cat}{list} = [];
}
my $lapsedCount = 0;

my %monthExpirations;
foreach my $supporterId (@supporterIds) {
  my $expiresOn = $sp->supporterExpirationDate($supporterId);
  my $expiresOnMonth = UnixDate(ParseDate($expiresOn), '%Y-%m');
  { no warnings 'uninitialized';  $monthExpirations{$expiresOnMonth}++; }

  my $isLapsed = ( (not defined $expiresOn) or $expiresOn le $TODAY);
  my $lapsesInOneWeek = ( (defined $expiresOn) and $expiresOn le $ONE_WEEK);
  my $lapsesInOneMonth = ( (defined $expiresOn) and $expiresOn le $ONE_MONTH);
  $expiresOn = "NO-FULL-SIGNUP" if not defined $expiresOn;
  $lapsedCount++ if $isLapsed;
  my %emails;
  my $email = $sp->getPreferredEmailAddress($supporterId);
  if (defined $email) {
    $emails{$email} = {};
  } else {
    %emails = $sp->getEmailAddresses($supporterId);
  }
  my(@emails) = keys(%emails);
  my $lastDonateDate = $sp->donorLastGave($supporterId);
  my $cat;
  if ($isLapsed) { $cat = '02-lapsed';} elsif ($lapsesInOneWeek) { $cat = '00-lapsing-this-week' }
  elsif ($lapsesInOneMonth) { $cat = '01-lapsing-this-month'; }

  push(@{$expireReport{$cat}{list}}, { expiresOn => $expiresOn, displayName => $sp->getDisplayName($supporterId),
                                              ledgerEntityId => $sp->getLedgerEntityId($supporterId), supporterId => $supporterId,
                                       emails => \@emails })
    if defined $cat;

  my $request = $sp->getRequest({ donorId => $supporterId, requestType => $REQUEST_NAME});

  if (defined $request) {
    if (defined $request->{fulfillDate}) {
      print STDERR "$supporterId lapsed on $expiresOn but recorded as renewed on $request->{fulfillDate}\n"
        if ( ($isLapsed or $lapsesInOneWeek) and $VERBOSE);
    } elsif ( (not $isLapsed) and (not $lapsesInOneWeek)) {
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
  print STDERR "$supporterId skipped since he is not lapsed\n" if ( (not $isLapsed and not $lapsesInOneWeek) and $VERBOSE > 1);
  next unless $isLapsed or $lapsesInOneWeek;


  open(MESSAGE, "<", $EMAIL_TEMPLATE);
  my @message;
  while (my $line = <MESSAGE> ) {
    $line =~ s/FIXME_LAST_DONATE_DATE/$lastDonateDate/g;
    push(@message, $line);
  }
  close MESSAGE;
  my $emailTo = join(' ', @emails);
  open(SENDMAIL, "|/usr/lib/sendmail -f \"$FROM_ADDRESS\" -oi -oem -- $emailTo $FROM_ADDRESS") or
    die "unable to run sendmail: $!";

  print STDERR "Sending to $supporterId at $emailTo who expires on $expiresOn\n";
  print SENDMAIL "To: ", join(', ', @emails), "\n";
  print SENDMAIL @message;

  close SENDMAIL;
  sleep 1;
  $sp->addRequest({donorId => $supporterId, requestType => $REQUEST_NAME});
}

my $subject = "Supporter lapsed report for $TODAY";
my $per = ( ($lapsedCount / scalar(@supporterIds)) * 100.00);
my $headerInfo = "$subject\n" . ("=" x length($subject)) .
  "\n\nWe have " . scalar(@supporterIds) . " supporters and $lapsedCount are lapsed.  That's " .
  sprintf("%.2f", $per) . "%.\nActive supporter count: " . (scalar(@supporterIds) - $lapsedCount) . "\n\n";
my $emailText .= $headerInfo;
my $allStaffEmailText = $headerInfo;
$emailText .= "\n     RENEWAL DUE COUNT BY MONTH\n";
$emailText .= "\n     ==========================\n";
$allStaffEmailText .= "\n     RENEWAL DUE COUNT BY MONTH\n";
$allStaffEmailText .= "\n     ==========================\n";

foreach my $month (sort { $a cmp $b } keys %monthExpirations) {
  my $xx = sprintf("$month: %5d\n", $monthExpirations{$month});
  $emailText .=  $xx;
  $allStaffEmailText .= $xx;
}
$emailText .= "\n";

foreach my $cat (sort { $a cmp $b } @lapseCategories) {
  my $heading = scalar(@{$expireReport{$cat}{list}}) . " " . $expireReport{$cat}{description};
  $emailText .= "$heading\n";
  $emailText .= "-" x length($heading);
  $emailText .= "\n";
  $allStaffEmailText .= "$heading\n";
  foreach my $sup (sort { ($cat eq '02-lapsed') ? ($b->{expiresOn} cmp $a->{expiresOn})
                            : ($a->{expiresOn} cmp $b->{expiresOn}) }
              @{$expireReport{$cat}{list}}) {
    my $threeYearTot = $sp->donorTotalGaveInPeriod(donorId => $sup->{supporterId},
                                                 startDate => $THREE_YEARS_AGO, endDate => $TODAY);
    my $twoYearTot = $sp->donorTotalGaveInPeriod(donorId => $sup->{supporterId},
                                                 startDate => $TWO_YEARS_AGO, endDate => $TODAY);
    
    $emailText .= "    $sup->{expiresOn}: $sup->{supporterId}, $sup->{ledgerEntityId}, $sup->{displayName},  ";
    $emailText .= "2YrTot: \$" . sprintf("%.2f", $twoYearTot).  ", 3YrTot: \$" . sprintf("%.2f", $threeYearTot);
    $emailText .= ", Emails: " . join(", ", @{$sup->{emails}});
    $emailText .= "\n";
  }
  $emailText .=  "\n";
}

my $email = Email::MIME->create(
    header_str => [
       To => $FROM_ADDRESS,
       From => $FROM_ADDRESS,
       Subject => $subject ],
    attributes => {
                   content_type => 'text/plain',
                   charset => 'utf-8',
                   encoding     => "quoted-printable",
                   disposition => 'inline' },
    body_str => $emailText);
open(SENDMAIL, "|/usr/lib/sendmail -f \"$FROM_ADDRESS\" -oi -oem -- $FROM_ADDRESS") or
  die "unable to run sendmail: $!";
print SENDMAIL $email->as_string;
close SENDMAIL;

my $allStaffEmail = Email::MIME->create(
    header_str => [
       To => $ALL_STAFF_ADDRESS,
       From => $FROM_ADDRESS,
       Subject => $subject ],
    attributes => {
                   content_type => 'text/plain',
                   charset => 'utf-8',
                   encoding     => "quoted-printable",
                   disposition => 'inline' },
    body_str => $allStaffEmailText);
open(SENDMAIL, "|/usr/lib/sendmail -f \"$FROM_ADDRESS\" -oi -oem -- $ALL_STAFF_ADDRESS") or
  die "unable to run sendmail: $!";
print SENDMAIL $allStaffEmail->as_string;
close SENDMAIL;
