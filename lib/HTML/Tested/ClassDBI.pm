=head1 NAME

HTML::Tested::ClassDBI - Enhances HTML::Tested to work with Class::DBI

=head1 SYNOPSIS

	package MyClass;
	use base 'HTML::Tested::ClassDBI';

	__PACKAGE__->make_tested_value('x');
	__PACKAGE__->bind_to_class_dbi(MyClassDBI => 
			x => 'col1');

=head1 DESCRIPTION

To be done.

=cut

use strict;
use warnings FATAL => 'all';

package HTML::Tested::ClassDBI;
use base 'HTML::Tested';
__PACKAGE__->mk_accessors(qw(class_dbi_object));
__PACKAGE__->mk_classdata('CDBI_Class');
__PACKAGE__->mk_classdata('Fields_To_Columns_Map');
__PACKAGE__->mk_classdata('PrimaryField');

our $VERSION = '0.04';

sub cdbi_bind_from_fields {
	my $class = shift;
	while (my ($n, $v) = each %{ $class->Widgets_Map }) {
		next unless exists $v->args->{cdbi_bind};
		$class->Fields_To_Columns_Map->{$n} =
			($v->args->{cdbi_bind} || $n);
	}
}

sub bind_to_class_dbi {
	my ($class, $dbi_class, %fields_to_cols_map) = @_;
	$class->PrimaryField(undef);
	$class->CDBI_Class($dbi_class);
	$class->Fields_To_Columns_Map(\%fields_to_cols_map);
	while (my ($n, $v) = each %fields_to_cols_map) {
		next unless $v eq 'Primary';
		$class->PrimaryField($n);
		last;
	}
	return if $class->PrimaryField;
	my @pc = $dbi_class->primary_columns;
	goto SET_PRIMARY_FIELD if @pc > 1;
	while (my ($n, $v) = each %fields_to_cols_map) {
		next unless $v eq $pc[0];
		$class->PrimaryField($n);
		last;
	};
	return if $class->PrimaryField;

SET_PRIMARY_FIELD:
	$class->PrimaryField('ht_id');
	$class->cdbi_bind_from_fields;
	$class->make_tested_value('ht_id');
}

sub _get_cdbi_pk_for_retrieve {
	my ($self, $res) = @_;
	$res ||= {};

	my @pc = $self->CDBI_Class->primary_columns;
	my $f = $self->PrimaryField;
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
	while (my ($f, $col) = each %{ $self->Fields_To_Columns_Map }) {
		next if $col eq 'Primary';
		my $val = ref($col) ? [ map { $cdbi->$_ } @$col ] : $cdbi->$col;
		$self->$f($val);
	}
	my $pc_field = $self->PrimaryField;
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
	while (my ($field, $col) = each %{ $self->Fields_To_Columns_Map }) {
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

sub cdbi_create_or_update {
	my $self = shift;
	return ($self->class_dbi_object || $self->_retrieve_cdbi_object)
		? $self->cdbi_update : $self->cdbi_create;
}

sub cdbi_construct {
	my $self = shift;
	return $self->CDBI_Class->construct($self->_get_cdbi_pk_for_retrieve);
}

sub cdbi_delete { shift()->cdbi_construct->delete; }

sub load_db_constraints {
	my $class = shift;
	my $arr = $class->CDBI_Class->db_Main->selectall_arrayref(<<ENDS
SELECT column_name FROM information_schema.columns WHERE
	table_name = ? and is_nullable = 'NO'
ENDS
	, undef, $class->CDBI_Class->table);
	my %not_nullable = map { ($_->[0], 1) } @$arr;
	while (my ($n, $v) = each %{ $class->Fields_To_Columns_Map }) {
		next unless $not_nullable{$v};
		HTML::Tested::Value::Form::Push_Constraints(
				$class->Widgets_Map->{$n}, '/.+/');
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

