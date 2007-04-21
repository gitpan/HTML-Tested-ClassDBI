use strict;
use warnings FATAL => 'all';

package HTML::Tested::ClassDBI::Field::Column;
use Carp;

sub verify_arg {
	my ($class, $root, $w, $arg) = @_;
	confess($w->name . ": $arg - unknown column. Wrong cdbi_bind usage")
		unless $root->CDBI_Class->find_column($arg);
}

sub bless_arg {
	my ($class, $root, $w, $arg) = @_;
	$class->verify_arg($root, $w, $arg);
	return bless([ $arg, $w->options->{cdbi_readonly} ], $class);
}

sub get_column_value {
	my ($self, $cdbi) = @_;
	my $c = $self->[0];
	return $cdbi->$c;
}

sub update_column {
	my ($self, $cdbi, $val) = @_;
	my $c = $self->[0];
	$cdbi->$c($val) unless $self->[1];
}

package HTML::Tested::ClassDBI::Field::Primary;
use base 'HTML::Tested::ClassDBI::Field::Column';

sub verify_arg {
	my ($class, $root, $w, $arg) = @_;
	push @{ $root->PrimaryFields }, $w->name;
	$root->ht_set_widget_option($w->name, "is_sealed", 1)
		unless exists $w->options->{is_sealed};
}

sub get_column_value {
	my ($self, $cdbi) = @_;
	my @pvals = map { $cdbi->$_ } $cdbi->primary_columns;
	return join('_', @pvals);
}

sub update_column {}

package HTML::Tested::ClassDBI::Field::Array;

sub bless_arg {
	my ($class, $root, $w, $arg) = @_;
	return bless([ map { HTML::Tested::ClassDBI::Field->do_bless_arg(
				$root, $w, $_) } @$arg ]);
}

sub get_column_value {
	my ($self, $cdbi) = @_;
	return [ map { $_->get_column_value($cdbi) } @$self ];
}

sub update_column {}

package HTML::Tested::ClassDBI::Field;

sub do_bless_arg {
	my ($class, $root, $w, $arg) = @_;
	if (ref($arg) eq 'ARRAY') {
		$class .= "::Array";
	} elsif ($arg eq 'Primary') {
		$class .= "::Primary";
	} else {
		$class .= "::Column";
	}
	return $class->bless_arg($root, $w, $arg);
}

sub new {
	my ($class, $root, $w) = @_;
	return unless exists $w->options->{cdbi_bind};

	my $arg = $w->options->{cdbi_bind} || $w->name;
	$class->do_bless_arg($root, $w, $arg);
}

1;
