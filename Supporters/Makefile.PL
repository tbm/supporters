use 5.020002;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Supporters',
    VERSION_FROM      => 'lib/Supporters.pm', # finds $VERSION, requires EU::MM from perl >= 5.5
    PREREQ_PM         => { DBI => 1.6, 'Sub::Override' => 0.09, 'Test::Exception' => 0.35, 'Mail::RFC822::Address' => 0.3 },
    ABSTRACT_FROM     => 'lib/Supporters.pm', # retrieve abstract from module
    AUTHOR            => 'Bradley M. Kuhn <bkuhn@ebb.org>',
    LICENSE           => 'agpl_3',
                         #NOTE: This is AGPLv3-or-later but MakeMaker doesn't offer -or-later options!!!
);
