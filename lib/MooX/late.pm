package MooX::late;

use 5.008;
use strict;
use warnings;
use Moo              qw( );
use Carp             qw( carp croak );
use Scalar::Util     qw( blessed );
use Module::Runtime  qw( is_module_name );

BEGIN {
	$MooX::late::AUTHORITY = 'cpan:TOBYINK';
	$MooX::late::VERSION   = '0.001';
}

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
	
	my $orig = $caller->can('has')
		or croak "Could not locate 'has' function to alter";
	
	$install_tracked->(
		$caller, has => sub
		{
			my ($name, %spec) = @_;
			
			$me->_process_isa($name, \%spec)
				if exists $spec{isa} && !ref $spec{isa};
			
			$me->_process_default($name, \%spec)
				if exists $spec{default} && !ref $spec{default};
			
			$me->_process_lazy_build($name, \%spec)
				if exists $spec{lazy_build} && $spec{lazy_build};
			
			return $orig->($name, %spec);
		},
	);

	$install_tracked->($caller, blessed => \&Scalar::Util::blessed);
	$install_tracked->($caller, confess => \&Carp::confess);	
}

sub _process_isa
{
	my ($me, $name, $spec) = @_;
	$spec->{isa} = _fatal_type_constraint($spec->{isa});
	return;
}

sub _process_default
{
	my ($me, $name, $spec) = @_;
	my $value = $spec->{default};
	$spec->{default} = sub { $value };
	return;
}

sub _process_lazy_build
{
	my ($me, $name, $spec) = @_;
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

# A bunch of stuff stolen from Moose::Util::TypeConstraints and
# MooX::Types::MooseLike::Base. I would have liked to have used
# MX:T:ML:B directly, but couldn't persuade it to play ball.
#
{
	my $valid_chars = qr{[\w:\.]};
	my $type_atom   = qr{ (?>$valid_chars+) }x;
	my $ws          = qr{ (?>\s*) }x;
	my $op_union    = qr{ $ws \| $ws }x;
	my ($type, $type_capture_parts, $type_with_parameter, $union, $any);
	if ($] >= 5.010)
	{
		my $type_pattern    = q{  (?&type_atom)  (?: \[ (?&ws)  (?&any)  (?&ws) \] )? };
		my $type_capture_parts_pattern   = q{ ((?&type_atom)) (?: \[ (?&ws) ((?&any)) (?&ws) \] )? };
		my $type_with_parameter_pattern  = q{  (?&type_atom)      \[ (?&ws)  (?&any)  (?&ws) \]    };
		my $union_pattern   = q{ (?&type) (?> (?: (?&op_union) (?&type) )+ ) };
		my $any_pattern     = q{ (?&type) | (?&union) };

		my $defines = qr{(?(DEFINE)
			(?<valid_chars>         $valid_chars)
			(?<type_atom>           $type_atom)
			(?<ws>                  $ws)
			(?<op_union>            $op_union)
			(?<type>                $type_pattern)
			(?<type_capture_parts>  $type_capture_parts_pattern)
			(?<type_with_parameter> $type_with_parameter_pattern)
			(?<union>               $union_pattern)
			(?<any>                 $any_pattern)
		)}x;

		$type                = qr{ $type_pattern                $defines }x;
		$type_capture_parts  = qr{ $type_capture_parts_pattern  $defines }x;
		$type_with_parameter = qr{ $type_with_parameter_pattern $defines }x;
		$union               = qr{ $union_pattern               $defines }x;
		$any                 = qr{ $any_pattern                 $defines }x;
	}
	else
	{
		$type                = qr{  $type_atom  (?: \[ $ws  (??{$any})  $ws \] )? }x;
		$type_capture_parts  = qr{ ($type_atom) (?: \[ $ws ((??{$any})) $ws \] )? }x;
		$type_with_parameter = qr{  $type_atom      \[ $ws  (??{$any})  $ws \]    }x;
		$union               = qr{ $type (?> (?: $op_union $type )+ ) }x;
		$any                 = qr{ $type | $union }x;
	}

	sub _parse_parameterized_type_constraint {
		{ no warnings 'void'; $any; }  # force capture of interpolated lexical
		$_[0] =~ m{ $type_capture_parts }x;
		return ( $1, $2 );
	}

	sub _detect_parameterized_type_constraint {
		{ no warnings 'void'; $any; }  # force capture of interpolated lexical
		$_[0] =~ m{ ^ $type_with_parameter $ }x;
	}

	sub _parse_type_constraint_union {
		{ no warnings 'void'; $any; }  # force capture of interpolated lexical
		my $given = shift;
		my @rv;
		while ( $given =~ m{ \G (?: $op_union )? ($type) }gcx ) {
			push @rv => $1;
		}
		( pos($given) eq length($given) )
		|| __PACKAGE__->_throw_error( "'$given' didn't parse (parse-pos="
			. pos($given)
			. " and str-length="
			. length($given)
			. ")" );
		@rv;
	}

	sub _detect_type_constraint_union {
		{ no warnings 'void'; $any; }  # force capture of interpolated lexical
		$_[0] =~ m{^ $type $op_union $type ( $op_union .* )? $}x;
	}
	
	sub _type_constraint
	{
		my $tc = shift;
		$tc =~ s/(^\s+|\s+$)//g;
		
		if ($tc =~ /^(
			Any|Item|Bool|Undef|Defined|Value|Str|Num|Int|
			Ref|CodeRef|RegexpRef|GlobRef|FileHandle|Object|
			ArrayRef|HashRef
		)$/x)
		{
			return {
				Any       => sub { 1 },
				Item      => sub { 1 },
				Undef     => sub { !defined $_[0] },
				Defined   => sub {  defined $_[0] },
				Value     => sub { !ref $_[0] },
				Bool      => sub {
					return 1 unless defined $_[0];
					!ref($_[0]) and $_[0]=~ /^(0|1|)$/;
				},
				Str       => sub { ref(\$_[0]) eq 'SCALAR' },
				Num       => sub { Scalar::Util::looks_like_number($_[0]) },
				Int       => sub { "$_[0]" =~ /^-?[0-9]+$/x },
				ScalarRef => sub { ref($_[0]) eq 'SCALAR' },
				ArrayRef  => sub { ref($_[0]) eq 'ARRAY' },
				HashRef   => sub { ref($_[0]) eq 'HASH' },
				CodeRef   => sub { ref($_[0]) eq 'CODE' },
				RegexpRef => sub { ref($_[0]) eq 'Regexp' },
				GlobRef   => sub { ref($_[0]) eq 'GLOB' },
				FileHandle=> sub { Scalar::Util::openhandle($_[0]) or blessed($_[0]) && $_[0]->isa('IO::Handle') },
				Object    => sub { blessed($_[0]) },
				ClassName => sub { is_module_name($_[0]) },
				RoleName  => sub { is_module_name($_[0]) },
			}->{$1};
		}

		if (_detect_type_constraint_union($tc))
		{
			my @isa =
				grep defined,
				map { _type_constraint($_) }
				_parse_type_constraint_union($tc);
			
			return sub {
				my $value = shift;
				foreach my $isa (@isa) {
					return 1 if eval { $isa->($value) };
				}
				return;
			};
		}
		
		if (_detect_parameterized_type_constraint($tc))
		{
			my ($outer, $inner) =
				_parse_parameterized_type_constraint($tc);
			$inner = _type_constraint($inner);
			
			if ($outer eq 'Maybe')
			{
				return sub { !defined($_[0]) or $inner->($_[0]) };
			}
			if ($outer eq 'ArrayRef')
			{
				return sub {
					return unless ref $_[0] eq 'ARRAY';
					foreach my $e (@{$_[0]}) {
						$inner->($e) or return;
					}
					return 1;
				};
			}
			if ($outer eq 'HashRef')
			{
				return sub {
					return unless ref $_[0] eq 'HASH';
					foreach my $e (values %{$_[0]}) {
						return unless $inner->($e);
					}
					return 1;
				};
			}
		}
		
		if (is_module_name($tc))
		{
			return sub { blessed($_[0]) and $_[0]->isa($tc) };
		}
		
		return;
	}
	
	sub _fatal_type_constraint
	{
		my $tc = _type_constraint(my $tc_name = shift);
		return sub { 1 } unless $tc;
		return sub { $tc->($_[0]) or die "value '$_[0]' is not a $tc_name" };
	}
}

1;

__END__

=head1 NAME

MooX::late - easily translate Moose code to Moo

=head1 SYNOPSIS

	package Foo;
	use MooX 'late';
	has bar => (is => 'ro', isa => 'Str');

or, without L<MooX>:

	package Foo;
	use Moo;
	use MooX::late;
	has bar => (is => 'ro', isa => 'Str');

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

Allows C<< isa => $type_constraint_string >> to work when defining attributes
for all Moose's built-in type constraints (and assumes other strings are
package names).

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
fruit.

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=MooX-late>.

=head1 SEE ALSO

The following modules bring additional Moose functionality to Moo:

=over

=item *

L<MooX::Override> - support override/super

=item *

L<MooX::Augment> - support augment/inner

=back

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

