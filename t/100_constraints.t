use strict;
use warnings FATAL => 'all';
use Test::More tests => 10;

use Test::TempDatabase;
use Class::DBI;
use Carp;

BEGIN { $SIG{__DIE__} = sub { diag(Carp::longmess(@_)); };
	use_ok( 'HTML::Tested::ClassDBI' ); 
}

my $tdb = Test::TempDatabase->create(dbname => 'ht_class_dbi_test_2',
			dbi_args => { RootClass => 'DBIx::ContextualFetch' });
my $dbh = $tdb->handle;
$dbh->do('SET client_min_messages TO error');

$dbh->do("CREATE TABLE table1 (i1 serial primary key, "
		. "t1 text not null, t2 text)");
is($dbh->{AutoCommit}, 1);

package CDBI_Base;
use base 'Class::DBI';

sub db_Main { return $dbh; }

package CDBI;
use base 'CDBI_Base';

__PACKAGE__->table('table1');
__PACKAGE__->columns(Essential => qw/i1 t1 t2/);
__PACKAGE__->sequence('table1_i1_seq');

package main;

is(CDBI->autoupdate, undef);
my $c1 = CDBI->create({ t1 => 'a', t2 => 'b' });
ok($c1);
is($c1->i1, 1);

package HTC;
use base 'HTML::Tested::ClassDBI';
__PACKAGE__->make_tested_form('v', children => [
		t1 => 'value', { cdbi_bind => '' },
		t2 => 'value', { cdbi_bind => '' }, ]);
__PACKAGE__->make_tested_value('ht_id', cdbi_bind => 'Primary');
__PACKAGE__->bind_to_class_dbi('CDBI');
__PACKAGE__->load_db_constraints;

package main;

my $o = HTC->new({ ht_id => 1 });
ok($o->cdbi_load);
is($o->t1, 'a');
is($o->t2, 'b');
is_deeply([ $o->validate_v ], []);

$o->t1(undef);
is_deeply([ $o->validate_v ], [ 't1', '/.+/' ]);

