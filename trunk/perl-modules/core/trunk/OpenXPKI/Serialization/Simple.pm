# OpenXPKI::Serialization::Simple.pm
# Written 2006 by Michael Bell
# (C) Copyright by OpenXPKI 2006

use strict;
use warnings;

package OpenXPKI::Serialization::Simple;

use OpenXPKI::Exception;

sub new
{
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {
                "DEBUG"     => 0,
                "SEPARATOR" => "\n",
               };

    bless $self, $class;

    my $keys = shift;
    $self->{DEBUG}     = $keys->{DEBUG}     if (exists $keys->{DEBUG});
    $self->{SEPARATOR} = $keys->{SEPARATOR} if (exists $keys->{SEPARATOR});

    if (length ($self->{SEPARATOR}) != 1)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERIALIZATION_SIMPLE_SEPARATOR_TOO_LONG");
    }
    if ($self->{SEPARATOR} =~ /^[0-9]$/)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERIALIZATION_SIMPLE_SEPARATOR_IS_NUMERIC");
    }

    return $self;
}

sub serialize
{
    my $self = shift;
    my $data = shift;

    return $self->__write_data($data);
}

sub __write_data
{
    my $self = shift;
    my $data = shift;
    my $msg  = "";

    if (ref $data eq "HASH")
    {
        ## it's a hash
        return $self->__write_hash ($data);
    }
    elsif (ref $data eq "ARRAY")
    {
        ## it's an array
        return $self->__write_array ($data);
    }
    else
    {
        ## it's a scalar
        return $self->__write_scalar ($data);
    }

    return $msg;
}

sub __write_hash
{
    my $self = shift;
    my $data = shift;
    my $msg  = "";

    foreach my $key (keys %{$data})
    {
        $msg .= length($key).$self->{SEPARATOR}.
                $key.$self->{SEPARATOR}.
                $self->__write_data ($data->{$key});
    }

    return "HASH".$self->{SEPARATOR}.
           length($msg).$self->{SEPARATOR}.
           $msg;
}

sub __write_array
{
    my $self = shift;
    my $data = shift;
    my $msg  = "";

    for (my $i = 0; $i<scalar @{$data}; $i++)
    {
        $msg .= $i.$self->{SEPARATOR}.
                $self->__write_data ($data->[$i]);
    }

    return "ARRAY".$self->{SEPARATOR}.
           length($msg).$self->{SEPARATOR}.
           $msg;
}

sub __write_scalar
{
    my $self = shift;
    my $data = shift;
    return "SCALAR".$self->{SEPARATOR}.
           length($data).$self->{SEPARATOR}.
           $data.$self->{SEPARATOR};
}

sub deserialize
{
    my $self = shift;
    my $msg  = shift;

    my $ret = $self->__read_data($msg);

    return $ret->{data};
}

sub __read_data
{
    my $self = shift;
    my $msg  = shift;

    if (substr ($msg, 0, 4) eq "HASH")
    {
        ## it's a hash
        return $self->__read_hash ($msg);
    }
    elsif (substr ($msg, 0, 5) eq "ARRAY")
    {
        ## it's an array
        return $self->__read_array ($msg);
    }
    else
    {
        ## it's a scalar
        return $self->__read_scalar ($msg);
    }

    return $msg;

}

sub __read_hash
{
    my $self = shift;
    my $msg  = shift;
       $msg  = substr ($msg, 5);  ## throw away "HASH\n"
    my %hash = ();

    ## read total length of hash
    my $ret     = $self->__read_int ($msg);
    my $hashmsg = substr ($ret->{msg}, 0, $ret->{int});
    $msg        = substr ($ret->{msg}, $ret->{int});

    while (length($hashmsg))
    {
        ## read length of hash key
        $ret = $self->__read_int ($hashmsg);
        ## read hash key
        my $key = substr ($ret->{msg},0,$ret->{int});
        ## read data
        my $data = $self->__read_data (substr ($ret->{msg},$ret->{int}+1));
        ## store data
        $hash{$key} = $data->{data};
        $hashmsg    = $data->{msg};
    }

    return {data => \%hash,
            msg  => $msg};
}

sub __read_array
{
    my $self  = shift;
    my $msg   = shift;
       $msg   = substr ($msg, 6);  ## throw away "ARRAY\n"
    my @array = ();

    ## read total length of array
    my $ret = $self->__read_int ($msg);
    my $arraymsg = substr ($ret->{msg}, 0, $ret->{int});
    $msg         = substr ($ret->{msg}, $ret->{int});

    while (length($arraymsg))
    {
        ## read position in array
        $ret = $self->__read_int ($arraymsg);
        ## read data
        my $res = $self->__read_data ($ret->{msg});
        ## store data
        $array[$ret->{int}] = $res->{data};
        $arraymsg           = $res->{msg};
    }

    return {data => \@array,
            msg  => $msg};
}

sub __read_scalar
{
    my $self   = shift;
    my $msg    = shift;
       $msg    = substr ($msg, 7);  ## throw away "SCALAR\n"
    my $length = 0;
    my $scalar = "";

    my $ret = $self->__read_int ($msg);
    $scalar = substr ($ret->{msg}, 0, $ret->{int});
    $msg    = substr ($ret->{msg}, $ret->{int}+1);

    return {data => $scalar,
            msg  => $msg}
}

sub __read_int
{
    my $self   = shift;
    my $msg    = shift;
    my $length = 0;

    while (substr ($msg, $length, 1) =~ /^[0-9]$/)
    {
        $length++;
    }
    $length = substr ($msg, 0, $length);
    $msg    = substr ($msg, length($length)+1);

    return {int => $length,
            msg => $msg}
}

1;
__END__

=head1 Description

=head1 Functions

=head2 new

=head2 serialize

=head2 deserialize

=head1 Syntax

We support hash references, array references and scalars
in any combination. The syntax is the following one:

hash         ::= 'HASH'.SEPARATOR.
                 [0-9]+.SEPARATOR. /* length of hash data */
                 hash_element+
hash_element ::= [1-9][0-9]*.SEPARATOR.    /* length of the hash key */
                 [a-zA-Z0-9_]+.SEPARATOR.  /* the hash key */
                 (hash|array|scalar)

array         ::= 'ARRAY'.SEPARATOR.
                  [0-9]+.SEPARATOR. /* length of array data */
                  array_element+
array_element ::= [0-9]+.SEPARATOR. /* position in the array */
                  (hash|array|scalar)

scalar ::= 'SCALAR'.SEPARATOR.
           [0-9]+.SEPARATOR. /* length of data */
           data.SEPARATOR

The SEPARATOR is one character long. It can be any non number.
The default separator is newline. The important thing is
that you can parse every structure without knowing the used
SEPARATOR.

Perhaps the good mathmatics notice that the last SEPARATOR
in the definition of a scalar is not necessary. This SEPARATOR
is only used to make the resulting structure better readable
for humans.
