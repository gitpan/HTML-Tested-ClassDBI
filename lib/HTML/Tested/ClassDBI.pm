=head1 NAME

HTML::Tested::ClassDBI - Enhances HTML::Tested to work with Class::DBI

=head1 SYNOPSIS

	package MyClass;
	use base 'HTML::Tested::ClassDBI';

	__PACKAGE__->make_tested_value('x');
	__PACKAGE__->bind_to_class_dbi(MyClassDBI => 
			col1 => 'x');

=head1 DESCRIPTION

To be done.

=cut

use strict;
use warnings FATAL => 'all';

package HTML::Tested::ClassDBI;
use base 'HTML::Tested';
__PACKAGE__->mk_accessors(qw(class_dbi_object));
__PACKAGE__->mk_classdata('CDBI_Class');
__PACKAGE__->mk_classdata('Columns_To_Fields_Map');

our $VERSION = '0.01';

sub bind_to_class_dbi {
	my ($class, $dbi_class, %cols_to_fields_map) = @_;
	$class->CDBI_Class($dbi_class);
	$class->Columns_To_Fields_Map(\%cols_to_fields_map);
}

sub _get_cdbi_pk_for_retrieve {
	my ($self, $res) = @_;
	$res ||= {};

	my @pc = $self->CDBI_Class->primary_columns;
	my $ctf = $self->Columns_To_Fields_Map;
	die "Multiple PKs is given, but no Primary set"
		if (@pc > 1 && !$ctf->{Primary});
	my $f = $ctf->{$pc[0]} || $ctf->{Primary};
	return undef unless $self->$f;
	my @vals = split('_', $self->$f);
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

sub _fill_in_from_class_dbi {
	my $self = shift;
	my $cdbi = $self->class_dbi_object;
	for my $col ($cdbi->columns) {
		my $f = $self->Columns_To_Fields_Map->{$col};
		$self->$f($cdbi->$col) if $f;
	}
	my $pc_field = $self->Columns_To_Fields_Map->{Primary} or return;
	my @pvals = map { $cdbi->$_ } $cdbi->primary_columns;
	$self->$pc_field($self->_make_cdbi_pk_value);
}

sub _retrieve_cdbi_object {
	my $self = shift;
	my $pk = $self->_get_cdbi_pk_for_retrieve;
	return unless defined($pk);
	my $cdbi = $self->CDBI_Class->retrieve(ref($pk) ? %$pk : $pk);
	$self->class_dbi_object($cdbi);
	return $cdbi;
}

sub cdbi_load {
	my $self = shift;
	my $cdbi = $self->_retrieve_cdbi_object or return;
	$self->_fill_in_from_class_dbi;
	return $cdbi;
}

sub query_class_dbi {
	my ($class, $func, @params) = @_;
	my @cdbis = $class->CDBI_Class->$func(@params);
	return [ map { 
		my $c = $class->new({ class_dbi_object => $_ });
		$c->_fill_in_from_class_dbi; 
		$c;
	} @cdbis ];
}

sub cdbi_create {
	my $self = shift;
	my %args;
	while (my ($col, $field) = each %{ $self->Columns_To_Fields_Map }) {
		if ($col eq 'Primary') {
			$self->_get_cdbi_pk_for_retrieve(\%args);
		} else {
			$args{$col} = $self->$field;
		}
	}
	my $res = $self->CDBI_Class->create(\%args);
	$self->class_dbi_object($res);
	return $res;
}

sub cdbi_update {
	my $self = shift;
	my %args;
	my $obj = $self->class_dbi_object;
	my %pc = map { ($_, 1) } $obj->primary_columns;
	while (my ($col, $field) = each %{ $self->Columns_To_Fields_Map }) {
		if ($col eq 'Primary') {
			$self->$field($self->_make_cdbi_pk_value);
		} elsif ($pc{$col}) {
			$self->$field($obj->$col);
		} else {
			$obj->$col($self->$field);
		}
	}
	$obj->update;
	return $obj;
}

sub cdbi_create_or_update {
	my $self = shift;
	return ($self->class_dbi_object || $self->_retrieve_cdbi_object)
		? $self->cdbi_update : $self->cdbi_create;
}

sub cdbi_delete {
	my $self = shift;
	$self->CDBI_Class->construct($self->_get_cdbi_pk_for_retrieve)->delete;
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

