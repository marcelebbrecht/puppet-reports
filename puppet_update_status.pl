#!/usr/bin/perl

# includes
use strict;
use warnings;
use YAML::XS 'LoadFile';
use Data::Dumper;
use List::MoreUtils qw(any uniq);

# settings
my $debug = 0;
my $nodeDirectory = "/opt/puppetlabs/server/data/puppetserver/yaml/node";
my $smtpSender = "foreman\@debian1.ukmtest.local";
my $smtpServer = "127.0.0.1";

# execution
print "Generating Reports, please wait ...\n";

# first get all recipients, sort and uniq
my @reportRecipients;
my @reportFiles = <$nodeDirectory/*.yaml>;
foreach my $reportFile (@reportFiles) {
	my $nodeConfig = LoadFile($reportFile);
	my $contactMail = $nodeConfig->{classes}->{updatereport}->{contactmail};
	push (@reportRecipients, $contactMail);
}
@reportRecipients = sort(uniq(@reportRecipients));

my %reports;
# now iterate over hosts and create report per recipient
foreach my $reportContact (@reportRecipients) {
	if ( $debug > 0 ) { print "Report for: ".$reportContact."\n"; }
	foreach my $reportFile (@reportFiles) {
		if ( $debug > 0 ) { print "\tTesting: ".$reportFile."\n"; }
		my $nodeConfig = LoadFile($reportFile);
		if ( $debug > 0 ) { print "\tTesting: ".$nodeConfig->{name}."\n"; }
		if ( $debug > 0 ) { print "\tTesting: ".$nodeConfig->{classes}->{updatereport}->{contactmail}."\n"; }
		if ( $nodeConfig->{classes}->{updatereport}->{contactmail} eq $reportContact ) {
			# collect common information
			if ( $debug > 0 ) { print "\t\tFound machine: ".$nodeConfig->{name}."\n"; }
			$reports{$reportContact}{$nodeConfig->{name}}{contactMail} = $nodeConfig->{classes}->{updatereport}->{contactmail};
			$reports{$reportContact}{$nodeConfig->{name}}{contactName} = $nodeConfig->{classes}->{updatereport}->{contactname};
			$reports{$reportContact}{$nodeConfig->{name}}{machineName} = $nodeConfig->{name};
			$reports{$reportContact}{$nodeConfig->{name}}{machineEnvironment} = $nodeConfig->{parameters}->{environment};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOwnerName} = $nodeConfig->{parameters}->{owner_name};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOwnerMail} = $nodeConfig->{parameters}->{owner_email};
			$reports{$reportContact}{$nodeConfig->{name}}{machinePuppetVersion} = $nodeConfig->{parameters}->{puppetversion};
			$reports{$reportContact}{$nodeConfig->{name}}{machineFqdn} = $nodeConfig->{parameters}->{fqdn};
			$reports{$reportContact}{$nodeConfig->{name}}{machineIp} = $nodeConfig->{parameters}->{ipaddress};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOsName} = $nodeConfig->{parameters}->{operatingsystem};
			$reports{$reportContact}{$nodeConfig->{name}}{machineOsVersion} = $nodeConfig->{parameters}->{operatingsystemrelease};
			$reports{$reportContact}{$nodeConfig->{name}}{machinePkg} = $nodeConfig->{parameters}->{package_provider};
			$reports{$reportContact}{$nodeConfig->{name}}{foremanHostgroup} = $nodeConfig->{parameters}->{hostgroup};

			# collect pkg dependent information: APT
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == apt\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "apt" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is APT!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{apt_has_updates}."\n"; }
				if ( $nodeConfig->{parameters}->{apt_has_updates} == 1 ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					my $list = join(" ",@{$nodeConfig->{parameters}->{apt_package_updates}});
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $list;
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				if ( $debug > 0 ) { print "\t\tTesting: has security updates: ".$nodeConfig->{parameters}->{apt_security_updates}."\n"; }
				if ( $nodeConfig->{parameters}->{apt_security_updates} > 0 ) {
					if ( $debug > 0 ) { print "\t\thas security updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
					my $list = join(" ",@{$nodeConfig->{parameters}->{apt_package_security_updates}});
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $list;
				} else {
					if ( $debug > 0 ) { print "\t\tno security updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: YUM
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == yum\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "yum" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is YUM!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{yum_updates_available}."\n"; }
				if ( $nodeConfig->{parameters}->{yum_updates_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $nodeConfig->{parameters}->{yum_updates_available_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				if ( $debug > 0 ) { print "\t\tTesting: has security updates: ".$nodeConfig->{parameters}->{yum_updates_available_security}."\n"; }
				if ( $nodeConfig->{parameters}->{yum_updates_available_security} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas security updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $nodeConfig->{parameters}->{yum_updates_available_security_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno security updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: Zypper (security patches are security updates, normal patches are updates, updates are updates)
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == zypper\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "zypper" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is Zypper!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{zypper_updates_available}."\n"; }
				if ( $nodeConfig->{parameters}->{zypper_updates_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "Updates: ".$nodeConfig->{parameters}->{zypper_updates_available_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "Updates: empty";
				}

				if ( $debug > 0 ) { print "\t\tTesting: has patches: ".$nodeConfig->{parameters}->{zypper_patches_available}."\n"; }
				if ( $nodeConfig->{parameters}->{zypper_patches_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList}.", Patches: ".$nodeConfig->{parameters}->{zypper_patches_available_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList}.", Patches: empty";
				}

				if ( $debug > 0 ) { print "\t\tTesting: has security patches: ".$nodeConfig->{parameters}->{zypper_patches_available_security}."\n"; }
				if ( $nodeConfig->{parameters}->{zypper_patches_available_security} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas security patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $nodeConfig->{parameters}->{zypper_patches_available_security_list};
				} else {
					if ( $debug > 0 ) { print "\t\tno security patches!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = "empty";
				}
			}

			# collect pkg dependent information: PKG (no difference between normal and security, so just copy)
			if ( $debug > 0 ) { print "\t\tTesting: ".$reports{$reportContact}{$nodeConfig->{name}}{machinePkg}." == pkg\n"; }
			if ( $reports{$reportContact}{$nodeConfig->{name}}{machinePkg} eq "pkg" ) {
				if ( $debug > 0 ) { print "\t\tTesting: is PKG!\n"; }

				if ( $debug > 0 ) { print "\t\tTesting: has updates: ".$nodeConfig->{parameters}->{pkg_updates_available}."\n"; }
				if ( $nodeConfig->{parameters}->{pkg_updates_available} eq "yes" ) {
					if ( $debug > 0 ) { print "\t\thas updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "true";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "unknown";
				} else {
					if ( $debug > 0 ) { print "\t\tno updates!\n"; }
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdates} = "false";
					$reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList} = "empty";
				}

				$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdates} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdates};
				$reports{$reportContact}{$nodeConfig->{name}}{hasSecurityUpdatesList} = $reports{$reportContact}{$nodeConfig->{name}}{hasUpdatesList};

			}
		} else {
			if ( $debug > 0 ) { print "\t\tUnknown machine: ".$nodeConfig->{name}."\n"; }
		}
	}
}

# now create report emails by contact

foreach my $reportContact (@reportRecipients) {
	print $reportContact."\n";
}

#print Dumper(%reports);
#print Dumper($reports{'ukmupdatesdebian@e2hosting.de'});
