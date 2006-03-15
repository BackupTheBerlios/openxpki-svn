## OpenXPKI::Server::ACL.pm 
##
## Written by Michael Bell 2006
## Copyright (C) 2006 by The OpenXPKI Project
## $Revision: 148 $

use strict;
use warnings;
use utf8;

package OpenXPKI::Server::ACL;

use English;
use OpenXPKI qw(debug);
use OpenXPKI::Exception;
use OpenXPKI::Server::Context qw( CTX );

## constructor and destructor stuff

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {
                DEBUG     => CTX('debug'),
               };

    bless $self, $class;

    my $keys = shift;
    $self->{DEBUG} = 1 if ($keys->{DEBUG});
    $self->debug ("start");

    return undef if (not $self->__load_config ());

    $self->debug ("end");
    return $self;
}

#############################################################################
##                         load the configuration                          ##
##                            (caching support)                            ##
#############################################################################

sub __load_config
{
    my $self = shift;
    $self->debug ("start");

    ## load all PKI realms

    my $realms = CTX('xml_config')->get_xpath_count (XPATH => 'pki_realm');
    for (my $i=0; $i < $realms; $i++)
    {
        $self->__load_pki_realm ({PKI_REALM => $i});
    }

    $self->debug ("leaving function successfully");
    return 1;
}

sub __load_pki_realm
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};

    my $name = CTX('xml_config')->get_xpath (XPATH   => ['pki_realm', 'name'],
                                             COUNTER => [$realm, 0]);
    $self->{PKI_REALM}->{$name}->{POS} = $realm;

    $self->__load_server      ({PKI_REALM => $name});
    $self->__load_roles       ({PKI_REALM => $name});
    $self->__load_permissions ({PKI_REALM => $name});

    return 1;
}

sub __load_server
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};
    my $pkiid = $self->{PKI_REALM}->{$realm}->{POS};

    $self->{SERVER_ID} = CTX('xml_config')->get_xpath (
                             XPATH   => ['common', 'database', 'server_id'],
                             COUNTER => [0, 0, 0]);
    my $servers = CTX('xml_config')->get_xpath_count (
                      XPATH   => ['pki_realm', 'acl', 'server'],
                      COUNTER => [$pkiid, 0]);
    for (my $i=0; $i < $servers; $i++)
    {
        my $value = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'server', 'id'],
                       COUNTER => [ $pkiid, 0, $i, 0]);
        my $name = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'server', 'name'],
                       COUNTER => [ $pkiid, 0, $i, 0]);
        if ($value == $self->{SERVER_ID})
        {
            $self->{SERVER_NAME} = $name;
            last;
        }
    }
    return 1;
}

sub __load_roles
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};
    my $pkiid = $self->{PKI_REALM}->{$realm}->{POS};

    my $roles = CTX('xml_config')->get_xpath_count (
                      XPATH   => ['pki_realm', 'acl', 'role'],
                      COUNTER => [$pkiid, 0]);
    for (my $i=0; $i < $roles; $i++)
    {
        my $role = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'role'],
                       COUNTER => [ $pkiid, 0, $i]);
        $self->{PKI_REALM}->{$realm}->{ROLES}->{$role} = 1;
    }
    return 1;
}

sub __load_permissions
{
    my $self  = shift;
    my $keys  = shift;
    my $realm = $keys->{PKI_REALM};
    my $pkiid = $self->{PKI_REALM}->{$realm}->{POS};

    my $perms = CTX('xml_config')->get_xpath_count (
                      XPATH   => ['pki_realm', 'acl', 'permission'],
                      COUNTER => [$pkiid, 0]);
    for (my $i=0; $i < $perms; $i++)
    {
        my $server = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'server'],
                       COUNTER => [ $pkiid, 0, $i]);
        my $activity = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'activity'],
                       COUNTER => [ $pkiid, 0, $i]);
        my $owner = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'affected_role'],
                       COUNTER => [ $pkiid, 0, $i]);
        my $user = CTX('xml_config')->get_xpath (
                       XPATH   => ['pki_realm', 'acl', 'permission', 'auth_role'],
                       COUNTER => [ $pkiid, 0, $i]);

        my @perms = ();

        ## evaluate server
        if ($server ne "*" and
            $server ne $self->{SERVER_NAME})
        {
            ## we only need the permissions for this server
            ## this reduces the propabilities of hash collisions
            next;
        }

        ## evaluate owner
        my @owners = ($owner);
           @owners = keys %{$self->{PKI_REALM}->{$realm}->{ROLES}}
               if ($owner eq "*");

        ## evaluate user
        my @users = ($user);
           @users = keys %{$self->{PKI_REALM}->{$realm}->{ROLES}}
               if ($user eq "*");

        ## an activity wildcard results in a *
        ## so we must check always for the activity and *
        ## before we throw an exception

        foreach $owner (@owners)
        {
            foreach $user (@users)
            {
                $self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user}->{$activity} = 1;
                $self->debug ("permission: $realm, $owner, $user, $activity");
            }
        }
    }
    return 1;
}

########################################################################
##                          identify the user                         ##
########################################################################

sub authorize
{
    my $self = shift;
    my $keys = shift;

    ## we need the following things:
    ##     - PKI realm
    ##     - auth_role
    ##     - affected_role
    ##     - activity

    my $realm    = CTX('session')->get_pki_realm();
    my $user     = CTX('session')->get_role();
    my $owner    = "Anonymous";
       $owner    = $keys->{AFFECTED_ROLE} if (exists $keys->{AFFECTED_ROLE} and
                                              defined $keys->{AFFECTED_ROLE});
    my $activity = $keys->{ACTIVITY};

    if (! defined $activity)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_ACL_AUTHORIZE_ACTIVITY_UNDEFINED",
            params  => {PKI_REALM     => $realm,
                        AFFECTED_ROLE => $owner,
                        AUTH_ROLE     => $user});
    }

    if (not exists $self->{PKI_REALM}->{$realm}->{ROLES}->{$owner})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_ACL_AUTHORIZE_ILLEGAL_AFFECTED_ROLE",
            params  => {PKI_REALM     => $realm,
                        ACTIVITY      => $activity,
                        AFFECTED_ROLE => $owner,
                        AUTH_ROLE     => $user});
    }

    if (not exists $self->{PKI_REALM}->{$realm}->{ROLES}->{$user})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_ACL_AUTHORIZE_ILLEGAL_AUTH_ROLE",
            params  => {PKI_REALM     => $realm,
                        ACTIVITY      => $activity,
                        AFFECTED_ROLE => $owner,
                        AUTH_ROLE     => $user});
    }

    if (not exists $self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user}->{$activity}
        and
        not exists $self->{PKI_REALM}->{$realm}->{ACL}->{$owner}->{$user}->{'*'})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_SERVER_ACL_AUTHORIZE_PERMISSION_DENIED",
            params  => {PKI_REALM     => $realm,
                        ACTIVITY      => $activity,
                        AFFECTED_ROLE => $owner,
                        AUTH_ROLE     => $user});
    }
    return 1;
}

1;
__END__
=head1 Description

The ACL module implements the authorization for the OpenXPKI core system.

=head1 Functions

=head2 new

is the constructor of the module. Only one parameter is accepted - DEBUG.
The constructor loads all ACLs of all PKI realms. Every PKI realm must include
an ACL section in its configuration. This configuration includes a definition
of all servers, all supported roles and all permissions.

=head2 authorize

is the function which grant the right to execute an activity. The function
needs two parameters ACTIVITY and AFFECTED_ROLE. The activity is the activity
which is performed by the workflow engine. The affected role is the role of
the object which is handled by the activity. If you create a request for
a certificate with the role "RA Operator" then the affected role is
"RA Operator".

The other needed parameters will be automatically determined via the active
session. It is not necessary to specify a PKI realm or the role of the logged
in user.

If the access is granted then function returns a true value. If the access
is denied then an exception is thrown.
