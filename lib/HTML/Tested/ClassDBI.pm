=head1 NAME

HTML::Tested::ClassDBI - Enhances HTML::Tested to work with Class::DBI

=head1 SYNOPSIS

  package MyClass;
  use base 'HTML::Tested::ClassDBI';
  
  __PACKAGE__->ht_add_widget('HTML::Tested::Value'
		  , id => cdbi_bind => "Primary");
  __PACKAGE__->ht_add_widget('HTML::Tested::Value', x => cdbi_bind => "");
  __PACKAGE__->bind_to_class_dbi('MyClassDBI');

  # And later somewhere ...
  # Query and load underlying Class::DBI:
  my $list = MyClass->query_class_dbi(search => x => 15);

  # or sync it to the database:
  $obj->cdbi_create_or_update;
	
=head1 DESCRIPTION

This class provides mapping between Class::DBI and HTML::Tested objects.

It inherits from HTML::Tested. Widgets created with C<ht_add_widget> can have
additional C<cdbi_bind> property.

After calling C<bind_to_class_dbi> you would be able to automatically
synchronize between HTML::Tested::ClassDBI instance and underlying Class::DBI.

=cut

use strict;
use warnings FATAL => 'all';

package HTML::Tested::ClassDBI;
use base 'HTML::Tested';
use Carp;
use HTML::Tested::ClassDBI::Field;

__PACKAGE__->mk_accessors(qw(class_dbi_object));
__PACKAGE__->mk_classdata('CDBI_Class');
__PACKAGE__->mk_classdata('Fields_To_Columns_Map');
__PACKAGE__->mk_classdata('PrimaryFields');
__PACKAGE__->mk_classdata('Field_Handlers');

our $VERSION = '0.11';

sub cdbi_bind_from_fields {
	my $class = shift;
	my $ftc = $class->Fields_To_Columns_Map; 
	for my $v (@{ $class->Widgets_List }) {
		my $f = HTML::Tested::ClassDBI::Field->new($class, $v) or next;
		my $n = $v->name;
		$class->Field_Handlers->{$n} = $f;
		$ftc->{$n} = ($v->options->{cdbi_bind} || $n);
	}
}

=head1 METHODS

=head2 $class->bind_to_class_dbi($cdbi_class)

Binds $class to $cdbi_class, by going over all fields declared with C<cdbi_bind>
option.

C<cdbi_bind> value could be one of the following:
name of the column, empty string for the column named the same as field or for
array of columns.

=cut
sub bind_to_class_dbi {
	my ($class, $dbi_class) = @_;
	$class->CDBI_Class($dbi_class);
	$class->Fields_To_Columns_Map({});
	$class->Field_Handlers({});
	$class->PrimaryFields([]);
	$class->cdbi_bind_from_fields;
	$class->_load_db_info;
}

sub _get_cdbi_pk_for_retrieve {
	my ($self, $res) = @_;
	$res ||= {};

	my @pc = $self->CDBI_Class->primary_columns;
	my $pf = $self->PrimaryFields;
	my ($pv) = grep { defined($_) } map { $self->$_ } @$pf;
	return undef unless defined($pv);
	my @vals = split('_', $pv);
	for (my $i = 0; $i < @pc; $i++) {
		$res->{$pc[$i]} = $vals[$i];
	}
	return $res;
}

sub _fill_in_from_class_dbi {
	my $self = shift;
	my $fhs = $self->Field_Handlers;
	my $cdbi = $self->class_dbi_object;
	while (my ($f, $h) = each %$fhs) {
		$self->$f($h->get_column_value($cdbi));
	}
}

sub _retrieve_cdbi_object {
	my $self = shift;
	my $pk = $self->_get_cdbi_pk_for_retrieve;
	return unless defined($pk);
	my $cdbi = $self->CDBI_Class->retrieve(ref($pk) ? %$pk : $pk);
	$self->class_dbi_object($cdbi);
	return $cdbi;
}

=head2 $obj->cdbi_load

Loads Class::DBI object using primary key field - the widget with special
C<cdbi_bind> => 'Primary'.

This method populates the rest of the bound fields with the values of loaded
Class::DBI object.

=cut
sub cdbi_load {
	my $self = shift;
	my $cdbi = $self->_retrieve_cdbi_object or return;
	$self->_fill_in_from_class_dbi;
	return $cdbi;
}

=head2 $class->query_class_dbi($func, @params)

This function loads underlying Class::DBI objects using query function $func
(e.g C<search>) with parameters contained in C<@params>.

For each of those objects new HTML::Tested::ClassDBI instance is created.

=cut
sub query_class_dbi {
	my ($class, $func, @params) = @_;
	my @cdbis = $class->CDBI_Class->$func(@params);
	return [ map { 
		my $c = $class->new({ class_dbi_object => $_ });
		$c->_fill_in_from_class_dbi; 
		$c;
	} @cdbis ];
}

=head2 $obj->cdbi_create($args)

Creates new database record using $obj fields.

Additional (optional) arguments are given by $args hash refernce.

=cut
sub cdbi_create {
	my ($self, $args) = @_;
	my $cargs = $self->_get_cdbi_pk_for_retrieve || {};
	while (my ($field, $col) = each %{ $self->Fields_To_Columns_Map }) {
		if ($col ne 'Primary' && !ref($col)) {
			$cargs->{$col} = $self->$field;
		}
	}
	while (my ($n, $v) = each %{ $args || {} }) {
		$cargs->{$n} = $v;
	}
	my $res = $self->CDBI_Class->create($cargs);
	$self->class_dbi_object($res);
	$self->_fill_in_from_class_dbi;
	return $res;
}

=head2 $obj->cdbi_update($args)

Updates database records using $obj fields.

Additional (optional) arguments are given by $args hash refernce.

=cut
sub cdbi_update {
	my ($self, $args) = @_;
	my $cdbi = $self->class_dbi_object || $self->_retrieve_cdbi_object
			|| return;
	my $fhs = $self->Field_Handlers;
	while (my ($field, $h) = each %$fhs) {
		$h->update_column($cdbi, $self->$field);
	}
	while (my ($n, $v) = each %{ $args || {} }) {
		$cdbi->$n($v);
	}
	$cdbi->update;
	$self->_fill_in_from_class_dbi;
	return $cdbi;
}

=head2 $obj->cdbi_create_or_update($args)

Calls C<cdbi_create> or C<cdbi_update> based on whether the database record
exists already.

Additional (optional) arguments are given by $args hash refernce.

=cut
sub cdbi_create_or_update {
	my ($self, $args) = @_;
	return ($self->class_dbi_object || $self->_retrieve_cdbi_object)
		? $self->cdbi_update($args) : $self->cdbi_create($args);
}

=head2 $obj->cdbi_construct

Constructs underlying Class::DBI object using $obj fields.

=cut
sub cdbi_construct {
	my $self = shift;
	return $self->CDBI_Class->construct(
			$self->_get_cdbi_pk_for_retrieve);
}

=head2 $obj->cdbi_delete

Deletes database record using $obj fields.

=cut
sub cdbi_delete { shift()->cdbi_construct->delete; }

my %_dt_fmts = (date => '%x', 'time' => '%X', timestamp => '%c');

sub _info_and_datetime {
	my ($class, $v) = @_;
	my $i = $class->CDBI_Class->pg_column_info($v) or return ();
	my ($t) = ($i->{type} =~ /^(\w+)/);
	return ($i, $_dt_fmts{$t});
}

sub _setup_datetime_for_array {
	my ($class, $w, $v) = @_;
	for (my $i = 0; $i < @$v; $i++) {
		next if $v->[$i] eq 'Primary';
		my (undef, $dt_fmt) = $class->_info_and_datetime($v->[$i]);
		next unless $dt_fmt;
		my $iopts = $w->options->{$i} || {};
		$w->setup_datetime_option($dt_fmt, $iopts);
		$w->options->{$i} = $iopts;
	}
}

sub _load_db_info {
	my $class = shift;
	while (my ($n, $v) = each %{ $class->Fields_To_Columns_Map }) {
		next if $v eq 'Primary';
		my $w = $class->ht_find_widget($n);
		if (ref($v) eq 'ARRAY') {
			$class->_setup_datetime_for_array($w, $v);
			next;
		}
		my ($i, $dt_fmt) = $class->_info_and_datetime($v);
		$w->push_constraint([ 'defined', '' ]) unless $i->{is_nullable};
		$w->setup_datetime_option($dt_fmt) if $dt_fmt;
	}
}

1;

=head1 AUTHOR

	Boris Sukholitko
	CPAN ID: BOSU
	
	boriss@gmail.com
	

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO

HTML::Tested, Class::DBI

=cut

