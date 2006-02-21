## OpenXPKI::Server::API.pm 
##
## Written by Michael Bell for the OpenXPKI project 2005
## Copyright (C) 2005 by The OpenXPKI Project
## $Revision$

use strict;
use warnings;
use utf8;

package OpenXPKI::Server::API;

## used modules
use English;
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Exception;

## we operate in static mode

sub new
{
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {DEBUG  => CTX('debug')};

    bless $self, $class;

    my $keys = { @_ };
    $self->{DEBUG}  = $keys->{DEBUG}  if ($keys->{DEBUG});
    
    return $self;
}

1;
__END__

=head1 Description

This is the interface which should be used by all user interfaces of OpenXPKI.
A user interface MUST NOT access the server directly. The only allowed
access is via this API. Any function which is not available in this API is
not for public use.
The API gets access to the server via the 'server' context object. This
object must be set before instantiating the API.

=head1 Functions

=head2 new

is the constructor. It accepts DEBUG as parameters. 
If DEBUG is a true value then the debugging code will be activated. Please
be warned that the general DEBUG mode is really noisy.
