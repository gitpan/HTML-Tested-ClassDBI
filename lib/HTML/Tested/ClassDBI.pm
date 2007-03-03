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
__PACKAGE__->mk_accessors(qw(class_dbi_object));
__PACKAGE__->mk_classdata('CDBI_Class');
__PACKAGE__->mk_classdata('Fields_To_Columns_Map');
__PACKAGE__->mk_classdata('PrimaryFields');

our $VERSION = '0.10';

sub cdbi_bind_from_fields {
	my $class = shift;
	my $ftc = $class->Fields_To_Columns_Map; 
	for my $v (@{ $class->Widgets_List }) {
		next unless exists $v->options->{cdbi_bind};
		my $n = $v->name;
		$ftc->{$n} = ($v->options->{cdbi_bind} || $n);
	}
}

sub bind_to_class_dbi {
	my ($class, $dbi_class) = @_;
	$class->CDBI_Class($dbi_class);
	$class->Fields_To_Columns_Map({});
	$class->PrimaryFields([]);
	$class->cdbi_bind_from_fields;
	my %ftc = %{ $class->Fields_To_Columns_Map };
	while (my ($n, $v) = each %ftc) {
		next unless ($v eq 'Primary'
			|| (ref($v) && grep { $_ eq 'Primary' } @$v));
		push @{ $class->PrimaryFields }, $n;
		my $opts = $class->ht_find_widget($n)->options;
		$class->ht_set_widget_option($n, "is_sealed", 1)
			unless exists $opts->{is_sealed};
	}
	$class->_load_db_info;
}

sub _get_cdbi_pk_for_retrieve {
	my ($self, $res) = @_;
	$res ||= {};

	my @pc = $self->CDBI_Class->primary_columns;
	my ($pv) = grep { defined($_) } map { $self->$_ }
			@{ $self->PrimaryFields };
	return undef unless defined($pv);
	my @vals = split('_', $pv);
	for (my $i = 0; $i < @pc; $i++) {
		$res->{$pc[$i]} = $vals[$i];
	}
	return $res;
}

sub _make_cdbi_pk_value {
	my $self = shift;
	my $cdbi = $self->class_dbi_object;
	my @pvals = map { $cdbi->$_ } $cdbi->primary_columns;
	return join('_', @pvals);
}

sub _get_column_value {
	my ($self, $col) = @_;
	my $val;
	if (ref($col) eq 'ARRAY') {
		$val = [ map { $self->_get_column_value($_) } @$col ];
	} elsif ($col eq 'Primary') {
		$val = $self->_make_cdbi_pk_value;
	} else {
		return $self->class_dbi_object->$col;
	}
}

sub _fill_in_from_class_dbi {
	my $self = shift;
	my $ftcm = $self->Fields_To_Columns_Map;
	while (my ($f, $col) = each %$ftcm) {
		$self->$f($self->_get_column_value($col));
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

=head1 METHODS

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

=head2 $obj->cdbi_create

Creates new database record using $obj fields.

=cut
sub cdbi_create {
	my $self = shift;
	my %args;
	while (my ($field, $col) = each %{ $self->Fields_To_Columns_Map }) {
		if ($col eq 'Primary') {
			$self->_get_cdbi_pk_for_retrieve(\%args);
		} else {
			$args{$col} = $self->$field;
		}
	}
	my $res = $self->CDBI_Class->create(\%args);
	$self->class_dbi_object($res);
	$self->_fill_in_from_class_dbi;
	return $res;
}

=head2 $obj->cdbi_update

Updates database records using $obj fields.

=cut
sub cdbi_update {
	my $self = shift;
	my %args;
	my $obj = $self->class_dbi_object;
	my %pc = map { ($_, 1) } $obj->primary_columns;
	while (my ($field, $col) = each %{ $self->Fields_To_Columns_Map }) {
		if ($col eq 'Primary') {
			$self->$field($self->_make_cdbi_pk_value);
		} elsif ($pc{$col}) {
			$self->$field($obj->$col);
		} elsif (!ref($col)) {
			$obj->$col($self->$field);
		}
	}
	$obj->update;
	return $obj;
}

=head2 $obj->cdbi_create_or_update

Calls C<cdbi_create> or C<cdbi_update> base on whether the database record
exists already.

=cut
sub cdbi_create_or_update {
	my $self = shift;
	return ($self->class_dbi_object || $self->_retrieve_cdbi_object)
		? $self->cdbi_update : $self->cdbi_create;
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

