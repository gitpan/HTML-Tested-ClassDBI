=head1 NAME

HTML::Tested::ClassDBI - Enhances HTML::Tested to work with Class::DBI

=head1 SYNOPSIS

  package MyClass;
  use base 'HTML::Tested::ClassDBI';
  
  __PACKAGE__->ht_add_widget('HTML::Tested::Value'
		  , id => cdbi_bind => "Primary");
  __PACKAGE__->ht_add_widget('HTML::Tested::Value'
		  , x => cdbi_bind => "");
  __PACKAGE__->ht_add_widget('HTML::Tested::Value::Upload'
  	, x => cdbi_upload => "largeobjectoid");
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
__PACKAGE__->mk_classdata('PrimaryFields');
__PACKAGE__->mk_classdata('Field_Handlers');

our $VERSION = '0.13';

sub cdbi_bind_from_fields {
	my $class = shift;
	for my $v (@{ $class->Widgets_List }) {
		my $f = HTML::Tested::ClassDBI::Field->new($class, $v) or next;
		$class->Field_Handlers->{$v->name} = $f;
	}
}

=head1 METHODS

=head2 $class->bind_to_class_dbi($cdbi_class)

Binds $class to $cdbi_class, by going over all fields declared with C<cdbi_bind>
or C<cdbi_upload> option.

C<cdbi_bind> option value could be one of the following:
name of the column, empty string for the column named the same as field or for
array of columns.

C<cdbi_upload> can be used to upload file into the database. Uploaded file is
stored as PostgreSQL's large object. Its OID is assigned to the bound column.

C<cdbi_upload_with_mime> uploads the file and prepends its mime type as a
header. Use HTML::Tested::ClassDBI::Upload->strip_mime_header to pull it from
the data.

C<cdbi_readonly> boolean option can be used to make its widget readonly thus
skipping its value during update. Read only widgets will not be validated.

C<cdbi_primary> boolean option is used to make an unique column behave as
primary key. C<cdbi_load> will use this field while retrieving the object from
the database.

=cut
sub bind_to_class_dbi {
	my ($class, $dbi_class) = @_;
	$class->CDBI_Class($dbi_class);
	$class->Field_Handlers({});
	$class->PrimaryFields({});
	$class->cdbi_bind_from_fields;
	$class->_load_db_info;
}

sub _get_cdbi_pk_for_retrieve {
	my $self = shift;
	my $res = {};

	my %pf = %{ $self->PrimaryFields };
	my ($pv, $pc);
	while (my ($k, $v) = each %pf) {
		$pv = $self->$k;
		next unless defined $pv;
		$pc = $v;
		last;
	}
	return undef unless defined($pv);
	my @vals = split('_', $pv);
	for (my $i = 0; $i < @$pc; $i++) {
		$res->{ $pc->[$i] } = $vals[$i];
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

This method populates the rest of the bound fields with values of the loaded
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
	$self->_update_fields($cargs, $args);
	my $res = $self->CDBI_Class->create($cargs);
	$self->class_dbi_object($res);
	$self->_fill_in_from_class_dbi;
	return $res;
}

sub _update_fields {
	my ($self, $cdbi, $args) = @_;
	my $fhs = $self->Field_Handlers;
	my $setter = ref($cdbi) eq 'HASH' 
		? sub { $cdbi->{ $_[0] } = $_[1]; }
		: sub { my $c = shift; $cdbi->$c(shift()); };
	while (my ($field, $h) = each %$fhs) {
		$h->update_column($setter, $self->$field);
	}
	while (my ($n, $v) = each %{ $args || {} }) {
		$setter->($n, $v);
	}
}

=head2 $obj->cdbi_update($args)

Updates database records using $obj fields.

Additional (optional) arguments are given by $args hash refernce.

=cut
sub cdbi_update {
	my ($self, $args) = @_;
	my $cdbi = $self->class_dbi_object || $self->_retrieve_cdbi_object
			|| return;
	$self->_update_fields($cdbi, $args);
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
sub cdbi_delete {
	my $c = shift()->cdbi_construct;
	$c->delete;
}

sub _load_db_info {
	my $class = shift;
	while (my ($n, $h) = each %{ $class->Field_Handlers }) {
		my $w = $class->ht_find_widget($n);
		$h->setup_type_info($class->CDBI_Class, $w);
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

