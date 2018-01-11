package Sisimai::ARF;
use feature ':5.10';
use strict;
use warnings;
use Sisimai::Bite::Email;
use Sisimai::RFC5322;

my $Re0 = {
    'content-type' => qr|multipart/mixed|,
    'report-type'  => qr/report-type=["]?feedback-report["]?/,
    'from'         => qr{(?:
         staff[@]hotmail[.]com\z
        |complaints[@]email-abuse[.]amazonses[.]com\z
        )
    }x,
    'subject'      => qr/complaint[ ]about[ ]message[ ]from[ ]/,
};
# http://tools.ietf.org/html/rfc5965
# http://en.wikipedia.org/wiki/Feedback_loop_(email)
# http://en.wikipedia.org/wiki/Abuse_Reporting_Format
#
# Netease DMARC uses:    This is a spf/dkim authentication-failure report for an email message received from IP
# OpenDMARC 1.3.0 uses:  This is an authentication failure report for an email message received from IP
# Abusix ARF uses        this is an autogenerated email abuse complaint regarding your network.
my $Re1 = {
    'begin'  => qr{\A(?>
         [Tt]his[ ]is[ ].+[ ]email[ ]abuse[ ]report
        |[Tt]his[ ]is[ ](?:
             an[ ]autogenerated[ ]email[ ]abuse[ ]complaint
            |an?[ ].+[ ]report[ ]for
            |a[ ].+[ ]authentication[ -]failure[ ]report[ ]for
            )
        )
    }x,
    'rfc822' => qr!\AContent-Type: (:?message/rfc822|text/rfc822-headers)!,
    'endof'  => qr/\A__END_OF_EMAIL_MESSAGE__\z/,
};

my $Indicators = Sisimai::Bite::Email->INDICATORS;
my $LongFields = Sisimai::RFC5322->LONGFIELDS;
my $RFC822Head = Sisimai::RFC5322->HEADERFIELDS;

sub description { return 'Abuse Feedback Reporting Format' }
sub smtpagent   { 'Feeback-Loop' }
sub headerlist  { return [] }
sub is_arf {
    # Email is a Feedback-Loop message or not
    # @param    [Hash] heads    Email header including "Content-Type", "From",
    #                           and "Subject" field
    # @return   [Integer]       1: Feedback Loop
    #                           0: is not Feedback loop
    my $class = shift;
    my $heads = shift || return 0;
    my $match = 0;

    if( $heads->{'content-type'} =~ $Re0->{'report-type'} ) {
        # Content-Type: multipart/report; report-type=feedback-report; ...
        $match = 1;

    } elsif( $heads->{'content-type'} =~ $Re0->{'content-type'} ) {
        # Microsoft (Hotmail, MSN, Live, Outlook) uses its own report format.
        # Amazon SES Complaints bounces
        if( $heads->{'from'} =~ $Re0->{'from'} && $heads->{'subject'} =~ $Re0->{'subject'} ) {
            # From: staff@hotmail.com
            # From: complaints@email-abuse.amazonses.com
            # Subject: complaint about message from 192.0.2.1
            $match = 1;
        }
    }
    return $match;
}

sub scan {
    # Detect an error for Feedback Loop
    # @param         [Hash] mhead       Message header of a bounce email
    # @options mhead [String] from      From header
    # @options mhead [String] date      Date header
    # @options mhead [String] subject   Subject header
    # @options mhead [Array]  received  Received headers
    # @options mhead [String] others    Other required headers
    # @param         [String] mbody     Message body of a bounce email
    # @return        [Hash, Undef]      Bounce data list and message/rfc822 part
    #                                   or Undef if it failed to parse or the
    #                                   arguments are missing
    my $class = shift;
    my $mhead = shift // return undef;
    my $mbody = shift // return undef;

    return undef unless is_arf(undef, $mhead);
    require Sisimai::Address;

    my $dscontents = [Sisimai::Bite::Email->DELIVERYSTATUS];
    my @hasdivided = split("\n", $$mbody);
    my $rfc822part = '';    # (String) message/rfc822-headers part
    my $previousfn = '';    # (String) Previous field name
    my $readcursor = 0;     # (Integer) Points the current cursor position
    my $recipients = 0;     # (Integer) The number of 'Final-Recipient' header
    my $rcptintext = '';    # (String) Recipient address in the message body
    my $commondata = {
        'diagnosis'    => '',   # Error message
        'from'         => '',   # Original-Mail-From:
        'rhost'        => '',   # Reporting-MTA:
    };
    my $arfheaders = {
        'feedbacktype' => '',   # Feedback-Type:
        'rhost'        => '',   # Source-IP:
        'agent'        => '',   # User-Agent:
        'date'         => '',   # Arrival-Date:
        'authres'      => '',   # Authentication-Results:
    };
    my $v = undef;

    # 3.1.  Required Fields
    #
    #   The following report header fields MUST appear exactly once:
    #
    #   o  "Feedback-Type" contains the type of feedback report (as defined
    #      in the corresponding IANA registry and later in this memo).  This
    #      is intended to let report parsers distinguish among different
    #      types of reports.
    #
    #   o  "User-Agent" indicates the name and version of the software
    #      program that generated the report.  The format of this field MUST
    #      follow section 14.43 of [HTTP].  This field is for documentation
    #      only; there is no registry of user agent names or versions, and
    #      report receivers SHOULD NOT expect user agent names to belong to a
    #      known set.
    #
    #   o  "Version" indicates the version of specification that the report
    #      generator is using to generate the report.  The version number in
    #      this specification is set to "1".
    #
    for my $e ( @hasdivided ) {
        # Read each line between $Re1->{'begin'} and $Re1->{'rfc822'}.
        unless( $readcursor ) {
            # Beginning of the bounce message or delivery status part
            if( $e =~ $Re1->{'begin'} ) {
                $readcursor |= $Indicators->{'deliverystatus'};
                next;
            }
        }

        unless( $readcursor & $Indicators->{'message-rfc822'} ) {
            # Beginning of the original message part
            if( $e =~ $Re1->{'rfc822'} ) {
                $readcursor |= $Indicators->{'message-rfc822'};
                next;
            }
        }

        if( $readcursor & $Indicators->{'message-rfc822'} ) {
            # After "message/rfc822"
            if( $e =~ m/X-HmXmrOriginalRecipient:[ ]*(.+)\z/ ) {
                # Microsoft ARF: original recipient.
                $dscontents->[-1]->{'recipient'} = Sisimai::Address->s3s4($1);
                $recipients++;
                # The "X-HmXmrOriginalRecipient" header appears only once so
                # we take this opportunity to hard-code ARF headers missing in
                # Microsoft's implementation.
                $arfheaders->{'feedbacktype'} = 'abuse';
                $arfheaders->{'agent'} = 'Microsoft Junk Mail Reporting Program';
            
            } elsif( $e =~ m/\AFrom:[ ]*(.+)\z/ ) {
                # Microsoft ARF: original sender.
                $commondata->{'from'} ||= Sisimai::Address->s3s4($1);
            
            } elsif( $e =~ m/\A([-0-9A-Za-z]+?)[:][ ]*(.+)\z/ ) {
                # Get required headers only
                my $lhs = lc $1;
                my $rhs = $2;

                $previousfn = '';
                next unless exists $RFC822Head->{ $lhs };

                $previousfn  = $lhs;
                $rfc822part .= $e."\n";
                $rcptintext  = $rhs if $lhs eq 'to';

            } elsif( $e =~ m/\A[ \t]+/ ) {
                # Continued line from the previous line
                $rfc822part .= $e."\n" if exists $LongFields->{ $previousfn };
                next if length $e;
                $rcptintext .= $e if $previousfn eq 'to';
            }
        } else {
            # Before "message/rfc822"
            next unless $readcursor & $Indicators->{'deliverystatus'};
            next unless length $e;

            # Feedback-Type: abuse
            # User-Agent: SomeGenerator/1.0
            # Version: 0.1
            # Original-Mail-From: <somespammer@example.net>
            # Original-Rcpt-To: <kijitora@example.jp>
            # Received-Date: Thu, 29 Apr 2009 00:00:00 JST
            # Source-IP: 192.0.2.1
            $v = $dscontents->[-1];

            if( $e =~ m/\AOriginal-Rcpt-To:[ ]+[<]?(.+)[>]?\z/ ||
                $e =~ m/\ARedacted-Address:[ ]([^ ].+[@])\z/ ) {
                # Original-Rcpt-To header field is optional and may appear any
                # number of times as appropriate:
                # Original-Rcpt-To: <user@example.com>
                # Redacted-Address: localpart@
                if( length $v->{'recipient'} ) {
                    # There are multiple recipient addresses in the message body.
                    push @$dscontents, Sisimai::Bite::Email->DELIVERYSTATUS;
                    $v = $dscontents->[-1];
                }
                $v->{'recipient'} = Sisimai::Address->s3s4($1);
                $recipients++;

            } elsif( $e =~ m/\AFeedback-Type:[ ]*([^ ]+)\z/ ) {
                # The header field MUST appear exactly once.
                # Feedback-Type: abuse
                $arfheaders->{'feedbacktype'} = $1;

            } elsif( $e =~ m/\AAuthentication-Results:[ ]*(.+)\z/ ) {
                # "Authentication-Results" indicates the result of one or more
                # authentication checks run by the report generator.
                #
                # Authentication-Results: mail.example.com;
                #   spf=fail smtp.mail=somespammer@example.com
                $arfheaders->{'authres'} = $1;

            } elsif( $e =~ m/\AUser-Agent:[ ]*(.+)\z/ ) {
                # The header field MUST appear exactly once.
                # User-Agent: SomeGenerator/1.0
                $arfheaders->{'agent'} = $1;

            } elsif( $e =~ m/\A(?:Received|Arrival)-Date:[ ]*(.+)\z/ ) {
                # Arrival-Date header is optional and MUST NOT appear more than
                # once.
                # Received-Date: Thu, 29 Apr 2010 00:00:00 JST
                # Arrival-Date: Thu, 29 Apr 2010 00:00:00 +0000
                $arfheaders->{'date'} = $1;

            } elsif( $e =~ m/\AReporting-MTA:[ ]*dns;[ ]*(.+)\z/ ) {
                # The header is optional and MUST NOT appear more than once.
                # Reporting-MTA: dns; mx.example.jp
                $commondata->{'rhost'} = $1;

            } elsif( $e =~ m/\ASource-IP:[ ]*(.+)\z/ ) {
                # The header is optional and MUST NOT appear more than once.
                # Source-IP: 192.0.2.45
                $arfheaders->{'rhost'} = $1;

            } elsif( $e =~ m/\AOriginal-Mail-From:[ ]*(.+)\z/ ) {
                # the header is optional and MUST NOT appear more than once.
                # Original-Mail-From: <somespammer@example.net>
                $commondata->{'from'} ||= Sisimai::Address->s3s4($1);

            } elsif( $e =~ $Re1->{'begin'} ) {
                # This is an email abuse report for an email message with the 
                #   message-id of 0000-000000000000000000000000000000000@mx 
                #   received from IP address 192.0.2.1 on 
                #   Thu, 29 Apr 2010 00:00:00 +0900 (JST)
                $commondata->{'diagnosis'} = $e;
            }
        } # End of if: rfc822
    }

    if( ($arfheaders->{'feedbacktype'} eq 'auth-failure' ) && $arfheaders->{'authres'} ) {
        # Append the value of Authentication-Results header
        $commondata->{'diagnosis'} .= ' '.$arfheaders->{'authres'}
    }

    unless( $recipients ) {
        # Insert pseudo recipient address when there is no valid recipient
        # address in the message.
        $dscontents->[-1]->{'recipient'} = Sisimai::Address->undisclosed('r');
        $recipients = 1;
    }

    unless( $rfc822part =~ m/\bFrom: [^ ]+[@][^ ]+\b/ ) {
        # There is no "From:" header in the original message
        if( length $commondata->{'from'} ) {
            # Append the value of "Original-Mail-From" value as a sender address.
            $rfc822part .= sprintf("From: %s\n", $commondata->{'from'});
        }
    }

    if( $mhead->{'subject'} =~ /complaint about message from ((\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3}))/ ) {
        # Microsoft ARF: remote host address.
        $arfheaders->{'rhost'} = $1;
        $commondata->{'diagnosis'} = sprintf(
            "This is a Microsoft email abuse report for an email message received from IP %s on %s",
            $arfheaders->{'rhost'}, $mhead->{'date'});
    }

    for my $e ( @$dscontents ) {
        if( $e->{'recipient'} =~ m/\A[^ ]+[@]\z/ ) {
            # AOL = http://forums.cpanel.net/f43/aol-brutal-work-71473.html
            $e->{'recipient'} = Sisimai::Address->s3s4($rcptintext);
        }
        map { $e->{ $_ } ||= $arfheaders->{ $_ } } keys %$arfheaders;
        delete $e->{'authres'};

        $e->{'softbounce'}  = -1;
        $e->{'diagnosis'} ||= $commondata->{'diagnosis'};
        $e->{'date'}      ||= $mhead->{'date'};

        unless( $e->{'rhost'} ) {
            # Get the remote IP address from the message body
            if( length $commondata->{'rhost'} ) {
                # The value of "Reporting-MTA" header
                $e->{'rhost'} = $commondata->{'rhost'};

            } elsif( $e->{'diagnosis'} =~ m/\breceived from IP address ([^ ]+)/ ) {
                # This is an email abuse report for an email message received
                # from IP address 24.64.1.1 on Thu, 29 Apr 2010 00:00:00 +0000
                $e->{'rhost'} = $1;
            }
        }
        $e->{'reason'}  = 'feedback';
        $e->{'command'} = '';
        $e->{'action'}  = '';
        $e->{'agent'} ||= __PACKAGE__->smtpagent;
    }
    return { 'ds' => $dscontents, 'rfc822' => $rfc822part };
}

1;
__END__

=encoding utf-8

=head1 NAME

Sisimai::ARF - Parser class for detecting ARF: Abuse Feedback Reporting Format.

=head1 SYNOPSIS

Do not use this class directly, use Sisimai::ARF.

    use Sisimai::ARF;
    my $v = Sisimai::ARF->scan($header, $body);

=head1 DESCRIPTION

Sisimai::ARF is a parser for email returned as a Feedback Loop report message.

=head1 FEEDBACK TYPES

=head2 B<abuse>

Unsolicited email or some other kind of email abuse.

=head2 B<fraud>

Indicates some kind of C<fraud> or C<phishing> activity.

=head2 B<other>

Any other feedback that does not fit into other registered types.

=head2 B<virus>

Report of a virus found in the originating message.

=head1 SEE ALSO

L<http://tools.ietf.org/html/rfc5965>

=head1 AUTHOR

azumakuniyuki

=head1 COPYRIGHT

Copyright (C) 2014-2018 azumakuniyuki, All rights reserved.

=head1 LICENSE

This software is distributed under The BSD 2-Clause License.

=cut
