=pod

This little file creates a test database for use by the tests.

=cut

use DBI;
use File::Spec;
use autodie;
use File::Slurp;
sub get_test_dbh {
  eval {
    unlink('test-supporters.db');
  };
  die $@ if ($@ and $@->isa('autodie::exception') and (not $@->matches('unlink')));


  my $dbh = DBI->connect("dbi:SQLite:dbname=test-supporters.db", "", "",
                                     { RaiseError => 1, sqlite_unicode => 1})
    or die $DBI::errstr;

  open (SQL, '<', File::Spec->catdir(File::Spec->updir(), 'sql', 'supporters-schema.sql'));
  while (my $line = <SQL>) {
    chomp $line;
    $line = join(' ',split(' ',$line));
    if ((substr($line,0,2) ne '--') and (substr($line,0,3) ne 'REM')) {
      if (substr($line,- 1,1) eq ';') {
        $query .= ' ' . substr($line,0,length($line) -1);
        $dbh->do($query) or warn "Can't execute statement in file, line $.: " . $dbh->errstr;
        $query = ' ';
      } else {
        $query .= ' ' . $line;
      }
    }
  }
  close(SQL);
  die $dbh->errstr if $dbh->errstr;
  return $dbh;
}

1;
