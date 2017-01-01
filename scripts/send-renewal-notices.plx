#!/usr/bin/perl

use strict;
use warnings;
use Encode;
use utf8;

use autodie qw(open close);

use DBI;
use Encode qw(encode decode);
use Email::MIME;
use Date::Manip::DM5;
use Supporters;

use LaTeX::Encode;
my $BIG_DONOR_CUTOFF = 500.00;

my $TODAY = UnixDate(ParseDate("today"), '%Y-%m-%d');
my $ONE_WEEK = UnixDate(DateCalc(ParseDate("today"), "+ 1 week"), '%Y-%m-%d');
my $ONE_MONTH = UnixDate(DateCalc(ParseDate("today"), "+ 1 month"), '%Y-%m-%d');
my $ONE_YEAR_AGO = UnixDate(DateCalc(ParseDate("today"), "- 1 year"), '%Y-%m-%d');
my $TWO_YEARS_AGO = UnixDate(DateCalc(ParseDate("today"), "- 2 years"), '%Y-%m-%d');
my $THREE_YEARS_AGO = UnixDate(DateCalc(ParseDate("today"), "- 3 years"), '%Y-%m-%d');

if (@ARGV < 8 ) {
  print STDERR "usage: $0 <SUPPORTERS_SQLITE_DB_FILE> <HOW_FAR_IN_ADVANCE> <REQUEST_NAME> <FROM_ADDRESS> <ALL_STAFF_ADDRESS> <EMAIL_TEMPLATE> <MONTHLY_SEARCH_REGEX> <ANNUAL_SEARCH_REGEX>  <VERBOSE> <LEDGER_CMD_LINE>\n";
  exit 1;
}

my($SUPPORTERS_SQLITE_DB_FILE, $HOW_FAR_IN_ADVANCE_CALC, $REQUEST_NAME, $FROM_ADDRESS, $ALL_STAFF_ADDRESS, $EMAIL_TEMPLATE, $MONTHLY_SEARCH_REGEX, $ANNUAL_SEARCH_REGEX, $VERBOSE,
   @LEDGER_CMN_LINE) = @ARGV;

my $HOW_FAR_IN_ADVANCE = UnixDate(DateCalc(ParseDate("today"), "+ " . $HOW_FAR_IN_ADVANCE_CALC), '%Y-%m-%d');
die "Unable to compute how far \"$HOW_FAR_IN_ADVANCE_CALC\" is from today" unless defined $HOW_FAR_IN_ADVANCE and $HOW_FAR_IN_ADVANCE =~ /[0-9]+\-[0-9]+\-[0-9]+/;

print "$HOW_FAR_IN_ADVANCE is how far in advance we're sending\n";

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
my(%activeCounter, %lapsedCounter);

my %monthExpirations;

my $isPaper = 0;
$isPaper = 1 if $EMAIL_TEMPLATE =~ /\.tex$/;

if ($isPaper) {
  open(ENVELOPES, ">envelopes-ready-to-send.tex") or die "unable to open labels: $!";
}
my $totalSupporters = 0;
my $sentCount = 0;
foreach my $supporterId (sort @supporterIds) {
  next unless $sp->isSupporter($supporterId);
  $totalSupporters++;
  my $expiresOn = $sp->supporterExpirationDate($supporterId);
  my $expiresOnMonth = UnixDate(ParseDate($expiresOn), '%Y-%m');
  { no warnings 'uninitialized';  $monthExpirations{$expiresOnMonth}++; }

  my $isLapsed = ( (not defined $expiresOn) or $expiresOn le $TODAY);
  my $lapsesInOneWeek = ( (defined $expiresOn) and $expiresOn le $ONE_WEEK);
  my $lapsesInOneMonth = ( (defined $expiresOn) and $expiresOn le $ONE_MONTH);
  my $lapsesSoon = ( (defined $expiresOn) and $expiresOn le $HOW_FAR_IN_ADVANCE);
  my $type = $sp->getType($supporterId);
  $expiresOn = "NO-FULL-SIGNUP" if not defined $expiresOn;
  if ($isLapsed) {
    $lapsedCount++;
    $lapsedCounter{$type}++ if defined $type;
  } else {
    $activeCounter{$type}++ if defined $type;
  }
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
        if ( ($isLapsed or $lapsesSoon) and $VERBOSE);
    } else {
      print STDERR "$supporterId received this renewal notice already on $request->{requestDate}\n"
        if $VERBOSE;
    }
    next;
  }
  print STDERR "$supporterId skipped since he is not lapsed\n" if ( (not $isLapsed and not $lapsesSoon) and $VERBOSE > 1);
  next unless $isLapsed or $lapsesSoon;

  my $displayName = $sp->getDisplayName($supporterId);
  if ($isPaper) {
    my $latexDisplayName = latex_encode($displayName);
    $latexDisplayName =~ s/\\unmatched\{0141\}/\L{}/g;
    $latexDisplayName =~ s/\\unmatched\{0142\}/\l{}/g;
    if ($latexDisplayName =~ /unmatched/) {
      print "Skipping $supporterId because the address has characters I can't print in LaTeX\n  name was: ", encode('UTF-8', $displayName), "\n";
      next;
    }
    my $postalAddress = $sp->getPreferredPostalAddress($supporterId);
    if (not defined $postalAddress) {
      my(@postalAddresses) = $sp->getPostalAddresses($supporterId);
      $postalAddress = $postalAddresses[0];
    }
    if ( (not defined $postalAddress) or  $postalAddress =~ /^\s*$/m or $postalAddress eq $displayName) {
      print "Skipping $supporterId because no postal address was available\n";
      next;
    }

    my $latexPostal = latex_encode($postalAddress);
    $latexPostal =~ s/\\unmatched\{0141\}/\L{}/g;
    $latexPostal =~ s/\\unmatched\{0142\}/\l{}/g;
    if ($latexPostal =~ /unmatched/) {
      print "Skipping $supporterId because the address has characters the post office will not accept\n  Address was: ", encode('UTF-8', $postalAddress), "\n";
      next;
    }
    $latexPostal = join(' \\\\ ', split('\n', $latexPostal));
    print ENVELOPES '\mlabel{}{TO: \\\\ ' . $latexPostal . "}\n";

    open(MESSAGE, "<", $EMAIL_TEMPLATE);
    open(LETTER, ">", sprintf("%4.4d", $sentCount++) . "-" . $supporterId . ".tex");
    while (my $line = <MESSAGE> ) {
      $line =~ s/FIXME-LAST-DONATE-DATE/$lastDonateDate/g;
      $line =~ s/FIXME-ADDRESS/$latexPostal/g;
      $line =~ s/FIXME-FULL-NAME/$latexDisplayName/g;
      print LETTER $line;
    }
    close LETTER;
    close MESSAGE;
  } else {
    open(MESSAGE, "<", $EMAIL_TEMPLATE);
    my @message;
    while (my $line = <MESSAGE> ) {
      $line =~ s/FIXME_LAST_DONATE_DATE/$lastDonateDate/g;
      push(@message, $line);
    }
    close MESSAGE;
    my $emailTo = join(' ', @emails);
    my $fullEmailLine = "";
    foreach my $email (@emails) {
      $fullEmailLine .= ", " if ($fullEmailLine ne "");
      my $line = "";
      if (defined $displayName) {
        $line .= "\"$displayName\" ";
      }
      $line .= "<$email>";
      $fullEmailLine .= Encode::encode("MIME-Header", $line);
    }
    open(SENDMAIL, "|/usr/lib/sendmail -f \"$FROM_ADDRESS\" -oi -oem -- $emailTo $FROM_ADDRESS") or
      die "unable to run sendmail: $!";

    print STDERR "Sending to $supporterId at $emailTo who expires on $expiresOn\n";
    print SENDMAIL "To: $fullEmailLine\n";
    print SENDMAIL @message;
    close SENDMAIL;
    sleep 1;
  }
  $sp->addRequest({donorId => $supporterId, requestType => $REQUEST_NAME});
}
if ($isPaper) {
  close ENVELOPES;
  exit 0;
}

my $subject = "Supporter lapsed report for $TODAY";
my $per = ( ($lapsedCount / $totalSupporters) * 100.00);
my $headerInfo = "$subject\n" . ("=" x length($subject)) .
  "\n\nWe have " . $totalSupporters . " supporters and $lapsedCount are lapsed.  That's " .
  sprintf("%.2f", $per) . "%.\nActive supporter count: " . ($totalSupporters - $lapsedCount) . "\n" .
  sprintf("    Of the active supporters, %.2f%% are monthly and %.2f%% are annual",
          ( ($activeCounter{Monthly} / ($totalSupporters - $lapsedCount)) * 100.00),
          ( ($activeCounter{Annual} / ($totalSupporters - $lapsedCount)) * 100.00)) . ".\n\n";

foreach my $type (keys %lapsedCounter) {
  $headerInfo .= sprintf("%7s:    Lapsed Count: %3d   Active Count: %3d\n",
                         $type, $lapsedCounter{$type}, $activeCounter{$type});
}
$headerInfo .= "\n";
my $emailText .= $headerInfo;
my $allStaffEmailText = $headerInfo;
my $bigDonorEmailText = "\n   LAPSED BIG DONORS\n" .
                          "   =================\n";

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
    my $oneYearTot = $sp->donorTotalGaveInPeriod(donorId => $sup->{supporterId},
                                                 startDate => $ONE_YEAR_AGO, endDate => $TODAY);
    $emailText .= "    $sup->{expiresOn}: $sup->{supporterId}, $sup->{ledgerEntityId}, $sup->{displayName},  ";
    $emailText .= "2YrTot: \$" . sprintf("%.2f", $twoYearTot).  ", 3YrTot: \$" . sprintf("%.2f", $threeYearTot);
    $emailText .= ", Emails: " . join(", ", @{$sup->{emails}});
    $emailText .= "\n";
    if ( ($threeYearTot / 3) > $BIG_DONOR_CUTOFF or ($twoYearTot / 2) > $BIG_DONOR_CUTOFF or
         $oneYearTot > $BIG_DONOR_CUTOFF) {
      $bigDonorEmailText .= "    $sup->{expiresOn}: $sup->{supporterId}, $sup->{ledgerEntityId}, $sup->{displayName},  ";
      $bigDonorEmailText .= "1YrTot: \$" . sprintf("%.2f", $oneYearTot) . "2YrTot: \$" .
        sprintf("%.2f", $twoYearTot).  ", 3YrTot: \$" . sprintf("%.2f", $threeYearTot);
    $bigDonorEmailText .= ", Emails: " . join(", ", @{$sup->{emails}}) . "\n";
    }
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

my $bigDonorLapsedEmail = Email::MIME->create(
    header_str => [
       To => $FROM_ADDRESS,
       From => $FROM_ADDRESS,
       Subject => "Big Donors Lapsed/Lapsing Soon (for $TODAY)"  ],
    attributes => {
                   content_type => 'text/plain',
                   charset => 'utf-8',
                   encoding     => "quoted-printable",
                   disposition => 'inline' },
    body_str => $bigDonorEmailText);
open(SENDMAIL, "|/usr/lib/sendmail -f \"$FROM_ADDRESS\" -oi -oem -- $FROM_ADDRESS") or
  die "unable to run sendmail: $!";
print SENDMAIL $bigDonorLapsedEmail->as_string;
close SENDMAIL;
