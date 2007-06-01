use strict;
use warnings FATAL => 'all';

package HTML::Tested::ClassDBI::Upload;
use Carp;
use File::MMagic;

sub new { return bless([ $_[1]->CDBI_Class, $_[2], $_[3] ], $_[0]); }

sub setup_type_info {}

sub strip_mime_header {
	my ($class, $buf) = @_;
	$buf =~ s/^MIME: ([^\n]+)\n//;
	return ($1, $buf);
}

sub _get_mime {
	my ($class, $fh) = @_;
	# Invoking file(2) command on $fh through IPC::Run3 doesn't work in
	# Apache.
	my $mm = File::MMagic->new;
	bless $fh, 'FileHandle';
	my $res = $mm->checktype_filehandle($fh);
	seek($fh, 0, 0) or confess "Unable to seek";
	return $res;
}

sub _dbh_write {
	my ($dbh, $lo_fd, $buf, $rlen) = @_;
	my $wlen = $dbh->func($lo_fd, $buf, $rlen, 'lo_write');
	defined($wlen) or confess "# Unable to lo_write $rlen";
	confess "# short write $rlen > $wlen" if $rlen != $wlen;
}

sub import_lo_object {
	my ($class, $dbh, $fh, $with_mime) = @_;
	confess "No filehandle is given!" unless $fh;
	confess "We should be in transaction" if $dbh->{AutoCommit};
	my $lo = $dbh->func($dbh->{pg_INV_WRITE}, 'lo_creat')
			or confess "# Unable to lo_creat";
	my $lo_fd = $dbh->func($lo, $dbh->{'pg_INV_WRITE'}, 'lo_open');
	defined($lo_fd) or confess "# Unable to lo_open $lo";

	my $mime = $class->_get_mime($fh) if ($with_mime);
	my ($buf, $rlen, $wlen);
	if ($mime) {
		$buf = "MIME: $mime\n";
		_dbh_write($dbh, $lo_fd, $buf, length $buf);
	}
	while (($rlen = sysread($fh, $buf, 4096))) {
		_dbh_write($dbh, $lo_fd, $buf, $rlen);
	}
	$dbh->func($lo_fd, 'lo_close') or confess "Unable to close $lo";
	return $lo;
}

sub update_column {
	my ($self, $setter, $val) = @_;
	return unless $val;
	my $lo = $self->import_lo_object($self->[0]->db_Main, $val, $self->[2]);
	$setter->($self->[1], $lo);
}

sub get_column_value {}

1;
