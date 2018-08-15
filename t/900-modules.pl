package Sisimai::Test::Modules;
sub list {
    my $v = [];
    my $f = [ qw|
        Address.pm
        ARF.pm
        Bite.pm
            Bite/Email.pm
                Bite/Email/Activehunter.pm
                Bite/Email/AmazonSES.pm
                Bite/Email/AmazonWorkMail.pm
                Bite/Email/Aol.pm
                Bite/Email/ApacheJames.pm
                Bite/Email/Bigfoot.pm
                Bite/Email/Biglobe.pm
                Bite/Email/Courier.pm
                Bite/Email/Domino.pm
                Bite/Email/EinsUndEins.pm
                Bite/Email/Exchange2003.pm
                Bite/Email/Exchange2007.pm
                Bite/Email/Exim.pm
                Bite/Email/EZweb.pm
                Bite/Email/Facebook.pm
                Bite/Email/FML.pm
                Bite/Email/GMX.pm
                Bite/Email/Google.pm
                Bite/Email/GSuite.pm
                Bite/Email/IMailServer.pm
                Bite/Email/InterScanMSS.pm
                Bite/Email/KDDI.pm
                Bite/Email/MailFoundry.pm
                Bite/Email/MailMarshalSMTP.pm
                Bite/Email/MailRu.pm
                Bite/Email/McAfee.pm
                Bite/Email/MessageLabs.pm
                Bite/Email/MessagingServer.pm
                Bite/Email/mFILTER.pm
                Bite/Email/MXLogic.pm
                Bite/Email/Notes.pm
                Bite/Email/Office365.pm
                Bite/Email/OpenSMTPD.pm
                Bite/Email/Outlook.pm
                Bite/Email/Postfix.pm
                Bite/Email/qmail.pm
                Bite/Email/ReceivingSES.pm
                Bite/Email/SendGrid.pm
                Bite/Email/Sendmail.pm
                Bite/Email/SurfControl.pm
                Bite/Email/UserDefined.pm
                Bite/Email/V5sendmail.pm
                Bite/Email/Verizon.pm
                Bite/Email/X1.pm
                Bite/Email/X2.pm
                Bite/Email/X3.pm
                Bite/Email/X4.pm
                Bite/Email/X5.pm
                Bite/Email/Yahoo.pm
                Bite/Email/Yandex.pm
                Bite/Email/Zoho.pm
            Bite/JSON.pm
                Bite/JSON/AmazonSES.pm
                Bite/JSON/SendGrid.pm
        Data.pm
            Data/JSON.pm
            Data/YAML.pm
        DateTime.pm
        MIME.pm
        Mail.pm
            Mail/Mbox.pm
            Mail/Maildir.pm
            Mail/Memory.pm
            Mail/STDIN.pm
        Message.pm
            Message/Email.pm
            Message/JSON.pm
        MDA.pm
        Order.pm
            Order/Email.pm
            Order/JSON.pm
        Reason.pm
            Reason/Blocked.pm
            Reason/ContentError.pm
            Reason/Delivered.pm
            Reason/ExceedLimit.pm
            Reason/Expired.pm
            Reason/Feedback.pm
            Reason/Filtered.pm
            Reason/HasMoved.pm
            Reason/HostUnknown.pm
            Reason/MailboxFull.pm
            Reason/MailerError.pm
            Reason/MesgTooBig.pm
            Reason/NoRelaying.pm
            Reason/NotAccept.pm
            Reason/NetworkError.pm
            Reason/OnHold.pm
            Reason/PolicyViolation.pm
            Reason/Rejected.pm
            Reason/SecurityError.pm
            Reason/SpamDetected.pm
            Reason/Suspend.pm
            Reason/SyntaxError.pm
            Reason/SystemError.pm
            Reason/SystemFull.pm
            Reason/TooManyConn.pm
            Reason/Undefined.pm
            Reason/UserUnknown.pm
            Reason/Vacation.pm
            Reason/VirusDetected.pm
        RFC2606.pm
        RFC3464.pm
        RFC3834.pm
        RFC5322.pm
        Rhost.pm
            Rhost/GoogleApps.pm
            Rhost/ExchangeOnline.pm
            Rhost/GoDaddy.pm
            Rhost/FrancePTT.pm
            Rhost/KDDI.pm
        SMTP.pm
            SMTP/Error.pm
            SMTP/Reply.pm
            SMTP/Status.pm
        String.pm
        Time.pm
    | ];

    push @$v, 'Sisimai.pm';
    for my $e ( @$f ) {
        push @$v, sprintf("Sisimai/%s", $e);
    }
    return $v;
}
1;
