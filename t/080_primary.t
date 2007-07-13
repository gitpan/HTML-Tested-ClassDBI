use strict;
use warnings FATAL => 'all';

use Test::More tests => 5;
use Test::TempDatabase;
use HTML::Tested qw(HTV);
use HTML::Tested::Value;

BEGIN { use_ok('HTML::Tested::ClassDBI'); }

my $tdb = Test::TempDatabase->create(dbname => 'ht_class_dbi_test',
		dbi_args => { RootClass => 'DBIx::ContextualFetch' });

my $dbh = $tdb->handle;
$dbh->do('SET client_min_messages TO error');

$dbh->do("CREATE TABLE table1 (id serial primary key
		, t1 text not null, t2 text not null unique)");

package CDBI_Base;
use base 'Class::DBI::Pg::More';

sub db_Main { return $dbh; }

package T1;
use base 'CDBI_Base';

__PACKAGE__->set_up_table('table1');

package HTC;
use base 'HTML::Tested::ClassDBI';
__PACKAGE__->ht_add_widget(::HTV, t2 => cdbi_bind => "", cdbi_primary => 1);
__PACKAGE__->ht_add_widget(::HTV, t1 => cdbi_bind => "");
__PACKAGE__->bind_to_class_dbi('T1');

package main;

my $t1 = T1->create({ t1 => "moo", t2 => "foo" });

my $h = HTC->new({ t2 => "foo" });
is($h->t2, "foo");

my $obj = $h->cdbi_load;
is($obj->id, $t1->id);
is($h->t2, "foo");
is($h->t1, "moo");
