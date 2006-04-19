use strict;
use warnings FATAL => 'all';
use Test::More tests => 61;

use Test::TempDatabase;
use Class::DBI;
use Carp;

BEGIN { $SIG{__DIE__} = sub { diag(Carp::longmess(@_)); };
	use_ok( 'HTML::Tested::ClassDBI' ); 
}

my $tdb = Test::TempDatabase->create(dbname => 'ht_class_dbi_test',
			dbi_args => { RootClass => 'DBIx::ContextualFetch' });
my $dbh = $tdb->handle;
$dbh->do('SET client_min_messages TO error');

$dbh->do("CREATE TABLE table1 (i1 serial primary key, t1 text, t2 text)");
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
__PACKAGE__->make_tested_value('id1');
__PACKAGE__->make_tested_value('text1');
__PACKAGE__->make_tested_value('text2');

__PACKAGE__->bind_to_class_dbi(CDBI => 
		id1 => i1 => text1 => t1 => text2 => 't2');

package main;

my $object = HTC->new();
isa_ok($object, 'HTC');

$object->id1(1);
ok($object->cdbi_load);
is($object->text1, 'a');
is($object->text2, 'b');
is_deeply($object->class_dbi_object, $c1);

my $o2 = HTC->new();
is($o2->cdbi_load, undef);
is($o2->text1, undef);

is_deeply([ CDBI->retrieve_all ], [ $c1 ]);
is_deeply(HTC->query_class_dbi('retrieve_all'), [ $object ]);
is_deeply(HTC->query_class_dbi('search', t1 => 'a'), [ $object ]);

$o2->text1('c');
$o2->text2('d');
my $c2 = $o2->cdbi_create_or_update;
is_deeply($c2, $o2->class_dbi_object);
is($c2->t1, 'c');
is($c2->t2, 'd');
is($c2->i1, 2);
is_deeply([ sort { $a->i1 <=> $b->i1 } CDBI->retrieve_all ], [ $c1, $c2 ]);

is($o2->id1, undef);
$o2->text2('e');
$c2 = $o2->cdbi_create_or_update;
is($o2->id1, 2);
is_deeply($c2, $o2->class_dbi_object);
is($c2->t2, 'e');
is_deeply([ sort { $a->i1 <=> $b->i1 } CDBI->retrieve_all ], [ $c1, $c2 ]);

is($c2->i1, 2);
$c2->t1('f');
$c2->update;
$c2->dbi_commit;
is($c2->t1, 'f');
is(CDBI->retrieve($c2->i1)->t1, 'f');

$dbh->do("CREATE TABLE table2 (
		id1 integer not null, id2 integer not null, txt text,
		unrelated text,
		primary key (id1, id2))");
package CDBI2;
use base 'CDBI_Base';
__PACKAGE__->table('table2');
__PACKAGE__->columns(Primary => qw/id1 id2/);
__PACKAGE__->columns(Essential => qw/txt unrelated/);

package main;

my $c21 = CDBI2->create({ id1 => 12, id2 => 14, txt => 'Hi' });
ok($c21);

package HTC2;
use base 'HTML::Tested::ClassDBI';

__PACKAGE__->make_tested_value('id');
__PACKAGE__->make_tested_value('txt');
__PACKAGE__->bind_to_class_dbi(CDBI2 => id => Primary => txt => 'txt');

package main;

my $htc2_arr = HTC2->query_class_dbi('retrieve_all');
is(@$htc2_arr, 1);
is($htc2_arr->[0]->id, '12_14');

$htc2_arr->[0]->id(undef);
$htc2_arr->[0]->txt('bb');
$htc2_arr->[0]->cdbi_create_or_update;

$htc2_arr = HTC2->query_class_dbi('retrieve_all');
is($htc2_arr->[0]->txt, 'bb');
is($htc2_arr->[0]->id, '12_14');

my $htc2 = HTC2->new;
$htc2->id('12_14');
$htc2->cdbi_load;
is($htc2->txt, 'bb');

$htc2 = HTC2->new;
$htc2->id('19_20');
$htc2->txt("more");
$htc2->cdbi_create_or_update;

$htc2_arr = HTC2->query_class_dbi('retrieve_all');
is(@$htc2_arr, 2);
is($htc2_arr->[1]->id, '19_20');
is($htc2_arr->[1]->txt, 'more');

$htc2 = HTC2->new;
$htc2->id('19_20');
$htc2->cdbi_delete;

$htc2_arr = HTC2->query_class_dbi('retrieve_all');
is(@$htc2_arr, 1);
is($htc2_arr->[0]->id, '12_14');

$htc2 = HTC2->new;
$htc2->id('19_20');
my $o = $htc2->cdbi_construct;
isa_ok($o, 'CDBI2');
is($o->id1, 19);
is($o->id2, 20);

package HTC1;
use base 'HTML::Tested::ClassDBI';
__PACKAGE__->make_tested_value('id1');
__PACKAGE__->make_tested_value('text1');
__PACKAGE__->make_tested_value('text2');

__PACKAGE__->bind_to_class_dbi(CDBI => 
		id1 => Primary => text1 => t1 => text2 => 't2');

package main;
$object = HTC1->new();

$object->id1(1);
ok($object->cdbi_load);
is($object->text1, 'a');

$object->class_dbi_object(undef);
$object->text2(undef);
$object->cdbi_create_or_update;

$c1 = CDBI->retrieve(1);
is($c1->t2, undef);

$object = HTC1->new();
$object->text2('mu');
$object->cdbi_create_or_update;
my $c3 = CDBI->retrieve(3);
is($c3->t2, 'mu');

$object = HTC1->new();
$object->id1(3);
$object->cdbi_delete;
is(CDBI->retrieve(3), undef);
is($object->can('ht_id'), undef);

package HTC3;
use base 'HTML::Tested::ClassDBI';
__PACKAGE__->make_tested_value('text1');
__PACKAGE__->make_tested_value('text2');

__PACKAGE__->bind_to_class_dbi(CDBI => text1 => t1 => text2 => 't2');

package main;
$object = HTC3->new();
is($object->PrimaryField, 'ht_id');
$object->ht_id(1);
ok($object->cdbi_load);
is($object->text1, 'a');

package HTC4;
use base 'HTML::Tested::ClassDBI';

__PACKAGE__->make_tested_value('txt');
__PACKAGE__->bind_to_class_dbi(CDBI2 => txt => 'txt');

package main;

$object = HTC4->new();
is($object->PrimaryField, 'ht_id');

package HTC5;
use base 'HTML::Tested::ClassDBI';
__PACKAGE__->make_tested_link('lnk');

__PACKAGE__->bind_to_class_dbi(CDBI => lnk => [ 't1','t2' ]);

package main;

my $c5 = CDBI->create({ t1 => 'a', t2 => 'b' });
$object = HTC5->new();

$object->ht_id($c5->id);
ok($object->cdbi_load);
is_deeply($object->lnk, [ 'a', 'b' ]);

ok($object->cdbi_create_or_update);

package HTC6;
use base 'HTML::Tested::ClassDBI';

__PACKAGE__->make_tested_value('t1', cdbi_bind => '');
__PACKAGE__->make_tested_edit_box('text2', cdbi_bind => 't2');
__PACKAGE__->make_tested_link('t2l', cdbi_bind => [ 't1', 't2' ]);
__PACKAGE__->make_tested_value('t2');
__PACKAGE__->bind_to_class_dbi('CDBI');

package main;

$c1->t2('b');
$c1->update;

$object = HTC6->new();
is($object->PrimaryField, 'ht_id');
$object->ht_id(1);
ok($object->cdbi_load);
is($object->t1, 'a');
is($object->text2, 'b');
is_deeply($object->t2l, [ 'a', 'b' ]);
is($object->t2, undef);

