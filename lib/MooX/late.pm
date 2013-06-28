use 5.008;
use strict;
use warnings;

package MooX::late;
our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.012';

use Moo              qw( );
use Carp             qw( carp croak );
use Scalar::Util     qw( blessed );
use Module::Runtime  qw( is_module_name );

BEGIN {
	package MooX::late::DefinitionContext;
	our $AUTHORITY = 'cpan:TOBYINK';
	our $VERSION   = '0.012';
	
	use Moo;
	use overload (
		q[""]    => 'to_string',
		q[bool]  => sub { 1 },
		fallback => 1,
	);
	
	has package  => (is => 'ro');
	has filename => (is => 'ro');
	has line     => (is => 'ro');
	
	sub to_string
	{
		my $self = shift;
		sprintf(
			'%s:%d, package %s',
			$self->filename,
			$self->line,
			$self->package,
		);
	}
	
	sub new_from_caller
	{
		my ($class, $level) = @_;
		$level = 0 unless defined $level;
		
		my ($p, $f, $c) = caller($level + 1);
		return $class->new(
			package  => $p,
			filename => $f,
			line     => $c,
		);
	}
};

sub import
{
	my $me = shift;
	my $caller = caller;
	
	my $install_tracked;
	{
		no warnings;
		if ($Moo::MAKERS{$caller})
		{
			$install_tracked = \&Moo::_install_tracked;
		}
		elsif ($Moo::Role::INFO{$caller})
		{
			$install_tracked = \&Moo::Role::_install_tracked;
		}
		else
		{
			croak "MooX::late applied to a non-Moo package"
				. "(need: use Moo or use Moo::Role)";
		}
	}
	
	my $orig = $caller->can('has')  # lolcat
		or croak "Could not locate 'has' function to alter";
	
	$install_tracked->(
		$caller, has => sub
		{
			my ($proto, %spec) = @_;
			my $context = "MooX::late::DefinitionContext"->new_from_caller(0);
			
			for my $name (ref $proto ? @$proto : $proto)
			{
				my $spec = +{ %spec }; # shallow clone
				$me->_process_isa($name, $spec, $context, $caller)
					if exists $spec->{isa} && !ref $spec->{isa};
				$me->_process_default($name, $spec, $context, $caller)
					if exists $spec->{default} && !ref $spec->{default};
				$me->_process_lazy_build($name, $spec, $context, $caller)
					if exists $spec->{lazy_build} && $spec->{lazy_build};
				
				$orig->($name, %$spec);
			}
			return;
		},
	);
	
	$install_tracked->($caller, blessed => \&Scalar::Util::blessed);
	$install_tracked->($caller, confess => \&Carp::confess);
}

my %registry;
sub _process_isa
{
	my ($me, $name, $spec, $context, $class) = @_;
	my $reg = (
		$registry{$class} ||= do {
			require MooX::late::TypeRegistry;
			"MooX::late::TypeRegistry"->new(chained => $class);
		}
	);
	$spec->{isa} = $reg->lookup($spec->{isa});
	return;
}

sub _process_default
{
	my ($me, $name, $spec, $context) = @_;
	my $value = $spec->{default};
	$spec->{default} = sub { $value };
	return;
}

sub _process_lazy_build
{
	my ($me, $name, $spec, $context) = @_;
	delete $spec->{lazy_build};
	
	$spec->{is}      ||= "ro";
	$spec->{lazy}    ||= 1;
	$spec->{builder} ||= "_build_$name";
	
	if ($name =~ /^_/)
	{
		$spec->{clearer}   ||= "_clear$name";
		$spec->{predicate} ||= "_has$name";
	}
	else
	{
		$spec->{clearer}   ||= "clear_$name";
		$spec->{predicate} ||= "has_$name";
	}
	
	return;
}

1;

__END__

=pod

=encoding utf8

=for stopwords superset MooX

=head1 NAME

MooX::late - easily translate Moose code to Moo

=head1 SYNOPSIS

   package Foo;
   use Moo;
   use MooX::late;
   has bar => (is => "ro", isa => "Str", default => "MacLaren's Pub");

(Examples for Moo roles in section below.)

=head1 DESCRIPTION

L<Moo> is a light-weight object oriented programming framework which aims
to be compatible with L<Moose>. It does this by detecting when Moose has
been loaded, and automatically "inflating" its classes and roles to full
Moose classes and roles. This way, Moo classes can consume Moose roles,
Moose classes can extend Moo classes, and so forth.

However, the surface syntax of Moo differs somewhat from Moose. For example
the C<isa> option when defining attributes in Moose must be either a string
or a blessed L<Moose::Meta::TypeConstraint> object; but in Moo must be a
coderef. These differences in surface syntax make porting code from Moose to
Moo potentially tricky. L<MooX::late> provides some assistance by enabling a
slightly more Moosey surface syntax.

MooX::late does the following:

=over

=item 1.

Allows C<< isa => $string >> to work when defining attributes for all
Moose's built-in type constraints (and assumes other strings are package
names).

This feature requires L<Types::Standard>.

=item 2.

Allows C<< default => $non_reference_value >> to work when defining
attributes.

=item 3.

Allows C<< lazy_build => 1 >> to work when defining attributes.

=item 4.

Exports C<blessed> and C<confess> functions to your namespace.

=back

Four features. It is not the aim of C<MooX::late> to make every aspect of
Moo behave exactly identically to Moose. It's just going after the low-hanging
fruit. So it does four things right now, and I promise that future versions
will never do more than seven.

=head2 Use in Moo::Roles

MooX::late should work in Moo::Roles, with no particular caveats.

   package MyRole;
   use Moo::Role;
   use MooX::late;

L<Package::Variant> can be used to build the Moo equivalent of
parameterized roles. MooX::late should work in roles built with
Package::Variant.

   use Package::Variant
      importing => ['MooX::Role' => ['late']],
      subs      => [ qw(has with) ];

=head2 Type constraints

Type constraint strings are interpreted using L<Type::Parser>, using the
type constraints defined in L<Types::Standard>. This provides a very slight
superset of Moose's type constraint syntax and built-in type constraints.

Any unrecognized string that looks like it might be a class name is
interpreted as a class type constraint.

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=MooX-late>.

=head1 SEE ALSO

C<MooX::late> uses L<Types::Standard> to check type constraints.

The following modules bring additional Moose functionality to Moo:

=over

=item *

L<MooX::Override> - support override/super

=item *

L<MooX::Augment> - support augment/inner

=back

L<MooX::HandlesVia> provides a native-traits-like feature for Moo. There
are plans afoot to add MooX::HandlesVia magic to MooX::late. 

L<MooX> allows you to load Moo plus multiple MooX extension modules in a
single line.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012-2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

