## TODO - consider merging this into Type::Tiny somewhere.
## Perhaps as Type::Util::dwim_lookup($type, %opts)???

package MooX::late::TypeRegistry;

use strict;
use warnings;

our $AUTHORITY = "cpan:TOBYINK";
our $VERSION   = "0.012";

use base "Type::Registry";

# Preload with standard types
sub new
{
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);
	$self->add_types(-Standard);
	# this hash key should never be used by the parent class
	$self->{"~~chained"} = $args{chained};
	return $self;
}

sub simple_lookup
{
	my $self = shift;
	
	my $r = $self->SUPER::simple_lookup(@_);
	return $r if defined $r;
	
	# Chaining! This is a fallback which looks up the
	# type constraint in the class' Type::Registry if
	# we couldn't find it ourselves.
	# 
	my $chained = "Type::Registry"->for_class($self->{"~~chained"});
	$r = eval { $chained->simple_lookup(@_) } unless $self == $chained;
	return $r if defined $r;
	
	# Lastly, if it looks like a class name, assume it's
	# supposed to be a class type.
	#
	if ($_[0] =~ /^\s*(\w+(::\w+)*)\s*$/sm)
	{
		require Type::Tiny::Class;
		return "Type::Tiny::Class"->new(class => $1);
	}
	
	# Give up already!
	return;
}

1;
