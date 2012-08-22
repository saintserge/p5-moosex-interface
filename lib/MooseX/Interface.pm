use 5.010;
use strict;
use warnings;
use utf8;
use Moose::Exporter 0 ();
use Moose::Role 2.00 ();
use Moose::Util 0 ();
use Moose::Util::MetaRole 0 ();
use constant 1.01 ();
use B::Hooks::EndOfScope 0 ();
use B::Hooks::Parser 0 ();
use Class::Load 0 ();

{
	package MooseX::Interface;
	
	BEGIN {
		$MooseX::Interface::AUTHORITY = 'cpan:TOBYINK';
		$MooseX::Interface::VERSION   = '0.002';
	
		*requires = \&Moose::Role::requires;
		*excludes = \&Moose::Role::excludes;
	}
	
	sub test_case (&;$)
	{
		Class::MOP::class_of( (scalar caller)[0] )->add_test_case(@_);
	}
	
	sub const
	{
		my ($meta, $name, $value) = @_;
		$meta->add_constant($name, $value);
	}
	
	sub extends
	{
		my ($meta, $other) = @_;
		Class::Load::load_class($other);
		confess("Tried to extent $other, but $other is not an interface; died")
			unless $other->meta->can('is_interface') && $other->meta->is_interface;
		Moose::Util::ensure_all_roles($meta->name, $other);
	}

	my ($import, $unimport) = Moose::Exporter->build_import_methods(
		with_meta => [qw( extends excludes const requires )],
		as_is     => [qw( test_case )],
	);
	
	sub unimport
	{
		goto $unimport;
	}
	
	sub import
	{
		my $OSE = '__PACKAGE__->meta->check_interface_integrity';
		B::Hooks::Parser::inject("; B::Hooks::EndOfScope::on_scope_end { $OSE };");
		goto $import;
	}

	sub init_meta
	{
		my $class   = shift;
		my %options = @_;
		
		my $iface = $options{for_class};
		Moose::Role->init_meta(%options);
		
		Moose::Util::MetaRole::apply_metaroles(
			for            => $iface,
			role_metaroles => {
				role => ['MooseX::Interface::Trait::Role'],
			}
		);
		
		Class::MOP::class_of($iface)->is_interface(1);
	}
}

{
	package MooseX::Interface::Trait::Method::Constant;
	use Moose;
	extends 'Moose::Meta::Method';
	BEGIN {
		$MooseX::Interface::Trait::Method::Constant::AUTHORITY = 'cpan:TOBYINK';
		$MooseX::Interface::Trait::Method::Constant::VERSION   = '0.002';
	}
}

{
	package MooseX::Interface::Trait::Role;
	use Moose::Role;
	use Contextual::Return;
	use namespace::clean;
	
	BEGIN {
		$MooseX::Interface::Trait::Role::AUTHORITY = 'cpan:TOBYINK';
		$MooseX::Interface::Trait::Role::VERSION   = '0.002';
	}

	has is_interface => (
		is      => 'rw',
		isa     => 'Bool',
		default => 0,
	);
	
	has test_cases => (
		is      => 'ro',
		isa     => 'ArrayRef',
		default => sub { [] },
	);
	
	sub add_constant
	{
		my ($meta, $name, $value) = @_;
		$meta->add_method(
			$name => 'MooseX::Interface::Trait::Method::Constant'->wrap(
				sub () { $value },
				name         => $name,
				package_name => $meta->name,
			),
		);
	}
	
	sub add_test_case
	{
		my ($meta, $coderef, $name) = @_;
		$name //= sprintf("Test case %d", @{ $meta->test_cases } + 1);
		push @{ $meta->test_cases }, [$coderef, $name];
	}
	
	sub test_implementation
	{
		my ($meta, $instance) = @_;
		confess("Parameter is not an object that implements the interface; died")
			unless blessed($instance) && $instance->DOES($meta->name);
		
		my @failed;
		foreach my $case ( @{ $meta->test_cases } )
		{
			my ($code, $name) = @$case;
			local $_ = $instance;
			push @failed, $name unless $code->();
		}
		
		return
			LIST     { @failed }
			BOOL     { @failed ? 0 : 1 }
			NUM      { scalar @failed }
			STR      { @failed ? 'not ok' : 'ok' }
			ARRAYREF { \@failed }
		;
	}

	sub find_problematic_methods
	{
		my $meta = shift;
		my @problems;
		
		foreach my $m ($meta->get_method_list)
		{
			# These shouldn't show up anyway.
			next if $m ~~ [qw(isa can DOES VERSION AUTHORITY)];
			
			my $M = $meta->get_method($m);
			
			# skip Interface->meta (that's allowed!)
			next if $M->isa('Moose::Meta::Method::Meta');
			
			# skip constants defined by constant.pm
			next if $constant::declared{ $M->fully_qualified_name };
		
			# skip constants defined by MooseX::Interface
			next if $M->isa('MooseX::Interface::Trait::Method::Constant');
			
			push @problems, $m;
		}
		
		return @problems;
	}

	sub check_interface_integrity
	{
		my $meta     = shift;
		
		if (my @problems = $meta->find_problematic_methods)
		{
			my $iface    = $meta->name;
			my $s        = (@problems==1 ? '' : 's');
			my $problems = join q[, ], sort @problems;
			$problems =~ s/, ([^,]+)$/, and $1/;
			
			confess(
				"Method$s defined within interface $iface ".
				"(try Moose::Role instead): $problems; died"
			);
		}
		
		foreach (qw( after around before override ))
		{
			my $has = "get_${_}_method_modifiers_map";
			if (keys %{ $meta->$has })
			{
				my $iface    = $meta->name;
				confess(
					"Method modifier defined within interface $iface ".
					"(try Moose::Role instead); died"
				);
			}
		}
	}
}

1;

__END__

=head1 NAME

MooseX::Interface - Java-style interfaces for Moose

=head1 SYNOPSIS

  package DatabaseAPI::ReadOnly
  {
    use MooseX::Interface;
    requires 'select';
  }
  
  package DatabaseAPI::ReadWrite
  {
    use MooseX::Interface;
    extends 'DatabaseAPI::ReadOnly';
    requires 'insert';
    requires 'update';
    requires 'delete';
  }
  
  package Database::MySQL
  {
    use Moose;
    with 'DatabaseAPI::ReadWrite';
    sub insert { ... }
    sub select { ... }
    sub update { ... }
    sub delete { ... }
  }
  
  Database::MySQL::->DOES('DatabaseAPI::ReadOnly');   # true
  Database::MySQL::->DOES('DatabaseAPI::ReadWrite');  # true

=head1 DESCRIPTION

MooseX::Interface provides something similar to the concept of interfaces
as found in many object-oriented programming languages like Java and PHP.

"What?!" I hear you cry, "can't this already be done in Moose using roles?"

Indeed it can, and that's precisely how MooseX::Interface works. Interfaces
are just roles with a few additional restrictions: 

=over

=item * You may not define any methods within an interface, except:

=over

=item * Moose's built-in C<meta> method, which will be defined for you;

=item * You may override methods from L<UNIVERSAL>; and

=item * You may define constants using the L<constant> pragma.

=back

=item * You may not define any attributes. (Attributes generate methods.)

=item * You may not define method modifiers.

=item * You can extend other interfaces, not normal roles.

=back

=head2 Functions

=over

=item C<< extends $interface >>

Extends an existing interface.

Yes, the terminology "extends" is used rather than "with".

=item C<< excludes $role >>

Prevents classes that implement this interface from also composing with
this role.

=item C<< requires $method >>

The name of a method (or attribute) that any classes implementing this
interface I<must> provide.

A future version of MooseX::Interface may provide a way to declare
method signatures.

=item C<< const $name => $value >>

Experimental syntactic sugar for declaring constants. It's probably not a
good idea to use this yet.

=item C<< test_case { BLOCK } $name >>

Experimental syntactic sugar for embedded test cases. This extends the idea
that an interface is a contract for classes to fulfil.

The block will be called with an instance of a class claiming to implement
the interface in C<< $_ >> and should return true if the instance passes the
test and false if it fails.

  package CalculatorAPI
  {
    use MooseX::Interface;
    
    requires 'add';
    test_case { $_->add(8, 2) == 10 };
    
    requires 'subtract';
    test_case { $_->subtract(8, 2) == 6 };
    
    requires 'multiply';
    test_case { $_->multiply(8, 2) == 16 };
    
    requires 'divide';
    test_case { $_->divide(8, 2) == 4 };
  }
  
  package Calculator
  {
    use Moose;
    with 'CalculatorAPI';
    sub add      { $_[1] + $_[2] }
    sub subtract { $_[1] - $_[2] }
    sub multiply { $_[1] * $_[2] }
    sub divide   { $_[1] / $_[2] }
  }
  
  my $result = CalculatorAPI->meta->test_implementation(
    Calculator->new,
  );

The result of C<test_implementation> is a L<Contextual::Return> object which
indicates success when evaluated in boolean context; indicates the number of
failures in numeric context; and provides TAP-like "ok" or "not ok" in
string context.

Do not rely on test cases being run in any particular order, or maintaining
any state between test cases. (Theoretically each test case could be run with
a separate instance of the implementing class.)

=back

=begin private

=item C<< init_meta >>

=end private

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=MooseX-Interface>.

=head1 SEE ALSO

L<Moose::Role>, L<MooseX::ABCD>.

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

