#! /usr/bin/perl -w

use English;
use strict;
use Cwd qw(cwd abs_path);
use File::Path qw(mkpath);
use File::Copy qw(copy);

use Getopt::Long qw(GetOptions);
Getopt::Long::Configure qw(posix_default no_ignore_case);

use Env qw(LDV_DEBUG);

use FindBin;

# Add some local Perl packages.
use lib("$FindBin::RealBin/../../shared/perl");

# Add some nonstandard local Perl packages.
#use LDV::Utils qw(print_debug_warning print_debug_normal print_debug_info
#	print_debug_debug print_debug_trace print_debug_all get_debug_level);

#######################################################################
# Subroutine prototypes.
#######################################################################

# Process command-line options. To see detailed description of these options
# run script with --help option.
# args: no.
# retn: nothing.
sub get_opt();

sub create_report($);

sub create_several_report(@);

#######################################################################
# Global variables
#######################################################################
my $debug_name = 'commit-tester-report';
my $report_file = "commit-tester-results.html";
my $num_of_files;
my $opt_do_rewrite;
my @several_files;
#######################################################################
# Main section.
#######################################################################
#get_debug_level($debug_name, $LDV_DEBUG);

get_opt();
unless($opt_do_rewrite)
{
	if(-f "$report_file")
	{
		print "File $report_file already exists. Do you want to rewrite it? (y/n) > ";
		my $ans = <STDIN>;
		chomp($ans);
		if($ans ne 'y')
		{
			print "Exiting without generating html report!\n";
			exit(1);
		}
	}
}
if($num_of_files == 1)
{
	create_report($several_files[0]);
}
else
{
	create_several_report(@several_files);
}
system("cp $report_file /var/www/html/main.html");
#######################################################################
# Subroutines.
#######################################################################
sub help()
{
	print (STDERR << "EOH");
NAME
	$PROGRAM_NAME: The program generates commit-tester html report form txt results.
SYNOPSIS
	$PROGRAM_NAME [option...]
OPTIONS
	-o, --result-file <file>
	   <file> is a file where results will be put in html format. If it isn't
	   specified then the output is placed to the file '$report_file'
	   in the current directory. If file was already existed you will be
	   asked if you want to rewrite it.
	-h, --help
	   Print this help and exit with an error.
	--files="<file1> <file2> ..."
		<file1> and next files are commit-tester txt results.
		It can be found at commit-tester-results/
	--rewrite
		Do not ask confirm of html file rewriting if it already exists.
EOH
	exit(1);
}
sub get_opt()
{
	my $opt_result_file;
	my $opt_help;
	my $opt_several_files;
	unless (GetOptions(
		'result-file|o=s' => \$opt_result_file,
		'help|h' => \$opt_help,
		'files=s' => \$opt_several_files,
		'rewrite|r' => \$opt_do_rewrite))
	{
		warn("Incorrect options may completely change the meaning! Please run script with the --help option to see how you may use this tool.");
		help();
	}
	help() if ($opt_help);
	@several_files = split(/\s+|;|,/, $opt_several_files);
	if ($opt_result_file)
	{
		$opt_result_file .= ".html" if ($opt_result_file !~ /.html$/);
		$report_file = $opt_result_file;
	}
	$num_of_files = @several_files;
	die "You should set --files=\"<files>\"" unless($num_of_files);
	my $i;
	for($i = 0; $i < $num_of_files; $i++)
	{
		die "Couldn't find file '$several_files[$i]'!" unless(-f $several_files[$i]);
		$several_files[$i] = abs_path($several_files[$i]);
	}
	#print_debug_trace("Results in html format will be written  to '$report_file'");
	#print_debug_debug("The command-line options are processed successfully. Number of files: '$num_of_files'");
}

sub create_report($)
{
	my $file_txt = shift;
	#print_debug_normal "Generating report from results: '$file_txt'";
	my $file_in;
	my $html_results;
	my $link;
	my $run_name = '';
	my $num_of_tasks = 0;
	my $sum_time = 0;
	my $sum_memory = 0;
	my $num_of_non_unknowns = 0;
	my %results_map;
	#print_debug_trace "Reading results..";
	open($file_in, '<', $file_txt) or die "Couldn't open file '$file_txt' for read: $ERRNO!";
	while(<$file_in>)
	{
		chomp($_);
		if($_ =~ /commit=(.*);memory=(.*);time=(.*);rule=(.*);kernel=(.*);driver=(.*);main=(.*);verdict=(.*);ideal_verdict=(.*);old_verdict=(.*?);#(.*)<@>(.*)$/)
		{
			$num_of_tasks++;
			$results_map{$num_of_tasks} = {
					'commit' => $1,
					'memory' => $2,
					'time' => $3,
					'rule' => $4,
					'kernel' => $5,
					'driver' => $6,
					'main' => $7,
					'new_verdict' => $8,
					'ideal_verdict' => $9,
					'old_verdict' => $10,
					'comment' => $11,
					'problems' => $12,
					'verdict_type' => 0
			};
			if($results_map{$num_of_tasks}{'comment'} =~ /^#/)
			{
				$results_map{$num_of_tasks}{'comment'} = $POSTMATCH;
				$results_map{$num_of_tasks}{'verdict_type'} = 1;
			}
			$sum_time += int($results_map{$num_of_tasks}{'time'})
				if($results_map{$num_of_tasks}{'time'} !~ /-/);
			
			if(($results_map{$num_of_tasks}{'memory'} !~ /-/) and
				($results_map{$num_of_tasks}{'new_verdict'} ne 'unknown'))
			{
				$sum_memory += int($results_map{$num_of_tasks}{'memory'});
				$num_of_non_unknowns++;
			}
		}
		elsif($_ =~ /link_to_results=(.*)/)
		{
			$link = $1;
		}
		elsif($_ =~ /name_of_runtask=(.*)/)
		{
			$run_name = $1;
		}
	}
	close($file_in);
	
	if($num_of_tasks == 0)
	{
		#print_debug_warning "Entry file '$file_txt' hasn't results!\n";
		exit(1);
	}
	#print_debug_trace "Results were read. Number of found tasks: $num_of_tasks";
	
	my $num_safe_safe = 0;
	my $num_safe_unsafe = 0;
	my $num_safe_unknown = 0;
	my $num_unsafe_safe = 0;
	my $num_unsafe_unsafe = 0;
	my $num_unsafe_unknown = 0;
	my $num_unknown_safe = 0;
	my $num_unknown_unsafe = 0;
	my $num_unknown_unknown = 0;
	my $num_ideal_safe_safe = 0;
	my $num_ideal_safe_unsafe = 0;
	my $num_ideal_safe_unknown = 0;
	my $num_ideal_unsafe_safe = 0;
	my $num_ideal_unsafe_unsafe = 0;
	my $num_ideal_unsafe_unknown = 0;
	my $num_of_found_bugs = 0;
	my $num_of_unknown_mains = 0;
	my $num_of_undev_rules = 0;

	#print_debug_trace "Writing html file..";
	open($html_results, '>', $report_file) or die "Couldn't open file '$html_results' for write: $ERRNO!";
	print($html_results "<!DOCTYPE html>
<meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\">\n<html>
	<head>
		<style type=\"text\/css\">
		body {background-color:#FFEBCD}
		p {color:#2F4F4F}
		th {color:#FFA500}
		td {background:#98FB98}
		td {color:#191970}
		th {background:#3CB371}
		</style>
	</head>
<body>

<h1 align=center style=\"color:#FF4500\"><u>Commit tests results</u></h1>

<p style=\"color:#483D8B\"><big>Result table:</big></p>

<table border=\"2\">\n<tr>
	<th>№</th>
	<th>Rule</th>
	<th>Kernel</th>
	<th>Commit</th>
	<th>Module</th>
	<th>Main</th>
	<th><small>Ideal->New verdict;<br>$run_name</small></th>
	<th>Old->New verdict</th>
	<th>Memory(KB)</th>
	<th>Time(ms)</th>
	<th>Comment</th>
	<th>Problems</th>\n</tr>");
	my $cnt = 0;
	for(my $i = 1; $i <= $num_of_tasks; $i++)
	{
		if(($results_map{$i}{'main'} ne 'n/a')
			and ($results_map{$i}{'rule'} ne 'n/a'))
		{
			$cnt++;
			$num_of_found_bugs++ if(($results_map{$i}{'new_verdict'} eq 'unsafe')
										and ($results_map{$i}{'verdict_type'} == 0)
										and ($results_map{$i}{'ideal_verdict'} eq 'unsafe'));
			$num_safe_unsafe++ if(($results_map{$i}{'old_verdict'} eq 'safe')
									  and ($results_map{$i}{'new_verdict'} eq 'unsafe'));
			$num_safe_unknown++ if(($results_map{$i}{'old_verdict'} eq 'safe')
									  and ($results_map{$i}{'new_verdict'} eq 'unknown'));
			$num_unsafe_safe++ if(($results_map{$i}{'old_verdict'} eq 'unsafe')
									  and ($results_map{$i}{'new_verdict'} eq 'safe'));
  			$num_safe_safe++ if(($results_map{$i}{'old_verdict'} eq 'safe')
									and ($results_map{$i}{'new_verdict'} eq 'safe'));
  			$num_unsafe_unsafe++ if(($results_map{$i}{'old_verdict'} eq 'unsafe')
										and ($results_map{$i}{'new_verdict'} eq 'unsafe'));
  			$num_unknown_unknown++ if(($results_map{$i}{'old_verdict'} eq 'unknown')
										  and ($results_map{$i}{'new_verdict'} eq 'unknown'));
			$num_unsafe_unknown++ if(($results_map{$i}{'old_verdict'} eq 'unsafe')
										 and ($results_map{$i}{'new_verdict'} eq 'unknown'));
			$num_unknown_unsafe++ if(($results_map{$i}{'old_verdict'} eq 'unknown')
										 and ($results_map{$i}{'new_verdict'} eq 'unsafe'));
			$num_unknown_safe++ if(($results_map{$i}{'old_verdict'} eq 'unknown')
									   and ($results_map{$i}{'new_verdict'} eq 'safe'));
			$num_ideal_safe_unsafe++ if(($results_map{$i}{'ideal_verdict'} eq 'safe')
											and ($results_map{$i}{'new_verdict'} eq 'unsafe'));
			$num_ideal_safe_safe++ if(($results_map{$i}{'ideal_verdict'} eq 'safe')
										  and ($results_map{$i}{'new_verdict'} eq 'safe'));
			$num_ideal_unsafe_unsafe++ if(($results_map{$i}{'ideal_verdict'} eq 'unsafe')
											  and ($results_map{$i}{'new_verdict'} eq 'unsafe'));
			$num_ideal_safe_unknown++ if(($results_map{$i}{'ideal_verdict'} eq 'safe')
											 and ($results_map{$i}{'new_verdict'} eq 'unknown'));
			$num_ideal_unsafe_safe++ if(($results_map{$i}{'ideal_verdict'} eq 'unsafe')
											and ($results_map{$i}{'new_verdict'} eq 'safe'));
			$num_ideal_unsafe_unknown++ if(($results_map{$i}{'ideal_verdict'} eq 'unsafe')
												and ($results_map{$i}{'new_verdict'} eq 'unknown'));

			print($html_results "\n<tr>
				<td>$cnt</td>
				<td>$results_map{$i}{'rule'}</td>
				<td>$results_map{$i}{'kernel'}</td>
				<td>$results_map{$i}{'commit'}</td>
				<td><small>$results_map{$i}{'driver'}</small></td>
				<td><small>$results_map{$i}{'main'}</small></td>
				<td style=\"color:#");
			if($results_map{$i}{'ideal_verdict'} ne $results_map{$i}{'new_verdict'})
			{
				print($html_results "CD2626");
			}
			else
			{
				print($html_results "191970");
			}
			print($html_results ";background:#9F79EE")
				if(($results_map{$i}{'verdict_type'} == 1)
					and ($results_map{$i}{'ideal_verdict'} eq 'unsafe'));
			print($html_results "\">$results_map{$i}{'ideal_verdict'}->$results_map{$i}{'new_verdict'}</td>
				<td");
			print($html_results " style=\"color:#CD2626\"")
				if($results_map{$i}{'old_verdict'} ne $results_map{$i}{'new_verdict'});
			print($html_results ">$results_map{$i}{'old_verdict'}->$results_map{$i}{'new_verdict'}</td>
				<td><small>$results_map{$i}{'memory'}</small></td>
				<td><small>$results_map{$i}{'time'}</small></td>
				<td><small>$results_map{$i}{'comment'}</small></td>\n");
			print {$html_results} "<td";
                        if ($results_map{$i}{'problems'} =~ /Memory/) {
				print {$html_results} " style=\"background:#7CFC00\"";
			}
			elsif ($results_map{$i}{'problems'} =~ /Time/) {
				print {$html_results} " style=\"background:#FFFF00\"";
			}
                        print {$html_results} "><small>$results_map{$i}{'problems'}</small></td>\n</tr>\n";
		}
		$num_of_unknown_mains++ if(($results_map{$i}{'main'} eq 'n/a')
										and ($results_map{$i}{'rule'} ne 'n/a'));
		$num_of_undev_rules++ if($results_map{$i}{'rule'} eq 'n/a');
	}
	print($html_results "<\/table>\n<br><br>");
	print($html_results "<hr>\n<a href=\"$link\">Link to visualizer with your results.</a><br>");
	print {$html_results} "<a href=\"http://gratinsky.vdi.mipt.ru/doc.html\">Documentation</a>";
	my $num_of_all_bugs = $num_ideal_unsafe_unsafe + $num_ideal_unsafe_safe + $num_ideal_unsafe_unknown;
	$sum_memory = int($sum_memory/$num_of_non_unknowns) if($sum_memory);
	$sum_time = $sum_time/60000;
	print($html_results "<hr><p style=\"color:#483D8B\"><big>Summary</big></p>\n<table border=\"1\">\n<tr>
		<th style=\"color:#00008B;background:#66CD00\"></th>
		<th style=\"color:#00008B;background:#66CD00\">Ideal->New verdict</th>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->unsafe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_ideal_unsafe_unsafe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->safe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_ideal_unsafe_safe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->unknown:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_ideal_unsafe_unknown</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->safe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_ideal_safe_safe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->unsafe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_ideal_safe_unsafe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->unknown:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_ideal_safe_unknown</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">No main</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_of_unknown_mains</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">No rule</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_of_undev_rules</td>\n</tr>\n</table>\n<hr>
		<p style=\"color:#483D8B\"><big>Target bugs</big></p>
		<p>Ldv-tools found $num_of_found_bugs of $num_of_all_bugs bugs;<br>Total number of bugs: $num_of_all_bugs;
		<br>Expended time: $sum_time minutes;<br>Average memory for each non-unknown task: $sum_memory KB;</p>\n");
	
	print($html_results "<hr><p style=\"color:#483D8B\"><big>Comparison with old verdicts</big></p><br>\n<table border=\"1\">\n<tr>
		<th style=\"color:#00008B;background:#66CD00\"></th>
		<th style=\"color:#00008B;background:#66CD00\">Old->New verdict</th>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->safe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_safe_safe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->unsafe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_unsafe_unsafe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->unsafe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_safe_unsafe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->unknown:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_safe_unknown</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->safe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_unsafe_safe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->unknown:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_unsafe_unknown</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unknown->safe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_unknown_safe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unknown->unsafe:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_unknown_unsafe</td>\n</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unknown->unknown:</th>
		<td style=\"color:#00008B;background:#CAFF70\">$num_unknown_unknown</td>\n</tr>\n</table>");
	my $cnt2 = 0;
	print($html_results "<hr><p style=\"color:#483D8B\"><big>Modules with unknown mains:</big></p>\n<table border=\"1\">\n<tr>
		<th style=\"background:#00C5CD;color:#191970\">№</th>
		<th style=\"background:#00C5CD;color:#191970\">Rule</th>
		<th style=\"background:#00C5CD;color:#191970\">Kernel</th>
		<th style=\"background:#00C5CD;color:#191970\">Commit</th>
		<th style=\"background:#00C5CD;color:#191970\">Module</th>
		<th style=\"background:#00C5CD;color:#191970\">Ideal verdict</th>
		<th style=\"background:#00C5CD;color:#191970\">Comment</th>\n</tr>");
	for(my $i = 1; $i <= $num_of_tasks; $i++)
	{
		if(($results_map{$i}{'main'} eq 'n/a') and ($results_map{$i}{'rule'} ne 'n/a'))
		{
			$cnt2++;
			print($html_results "<tr>
			<td style=\"background:#87CEFF;color:#551A8B\">$cnt2</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'rule'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'kernel'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'commit'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'driver'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'ideal_verdict'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'comment'}</td>\n</tr>");
		}
	}
	print($html_results "</table>\n<br>");
	my $cnt3 = 0;
	print($html_results "<hr><p style=\"color:#483D8B\"><big>Undeveloped rules:</big></p><table border=\"1\">\n<tr>
			<th style=\"background:#CD5555;color:#363636\">№</th>
			<th style=\"background:#CD5555;color:#363636\">Kernel</th>
			<th style=\"background:#CD5555;color:#363636\">Commit</th>
			<th style=\"background:#CD5555;color:#363636\">Module</th>
			<th style=\"background:#CD5555;color:#363636\">Ideal verdict</th>
			<th style=\"background:#CD5555;color:#363636\">Comment</th>
			</tr>");
	for(my $i = 1; $i <= $num_of_tasks; $i++)
	{
		if($results_map{$i}{'rule'} eq 'n/a')
		{
			$cnt3++;
			print($html_results "<tr>
			<td style=\"background:#FFC1C1;color:#363636\">$cnt3</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'kernel'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'commit'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'driver'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'ideal_verdict'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'comment'}</td>\n</tr>");
		}
	}
	print($html_results "\n</table>\n</body>\n</html>");
	close($html_results);
	#print_debug_normal "Report '$report_file' was successfully generated";
}

sub create_several_report(@)
{
	my @files = @_;
	my $num_of_tasks = 0;
	my @links;
	my @full_names;
	my @names;
	my @sum_time;
	my @sum_good_time;
	my @sum_memory;
	my %results_map;
	for(my $i = 0; $i < $num_of_files; $i++)
	{
		#print_debug_trace "file-$i: '$files[$i]'";
		push(@links, 'n/a');
		push(@full_names, 'n/a');
		push(@names, '1st') if($i == 0);
		push(@names, '2nd') if($i == 1);
		push(@names, '3d') if($i == 2);
		my $tmp_var = $i + 1;
		$tmp_var .= 'th';
		push(@names, "$tmp_var") if($i > 2);
		$sum_time[$i] = 0;
		$sum_good_time[$i] = 0;
		$sum_memory[$i] = 0;
	}
	open(my $first_file, '<', $files[0]) or die "Couldn't open file '$files[0]' for read: $ERRNO!";
	while(<$first_file>)
	{
		chomp($_);
		if($_ =~ /^commit=(.*);memory=(.*);time=(.*);rule=(.*);kernel=(.*);driver=(.*);main=(.*);verdict=(.*);ideal_verdict=(.*);old_verdict=.*?;#(.*)<@>(.*)$/)
		{
			$num_of_tasks++;
			$results_map{$num_of_tasks} = {
					'commit' => $1,
					'memory' => $2,
					'time' => $3,
					'rule' => $4,
					'kernel' => $5,
					'driver' => $6,
					'main' => $7,
					'verdict0' => $8,
					'ideal_verdict' => $9,
					'comment' => $10,
					'problems' => $11,
					'verdict_type' => 0
			};
			for(my $i = 1; $i < $num_of_files; $i++)
			{
				$results_map{$num_of_tasks}{"verdict$i"} = 'n/a';
			}
			if($results_map{$num_of_tasks}{'comment'} =~ /^#/)
			{
				$results_map{$num_of_tasks}{'comment'} = $POSTMATCH;
				$results_map{$num_of_tasks}{'verdict_type'} = 1;
			}
			$results_map{$num_of_tasks}{'problems'} = '-'
				if($results_map{$num_of_tasks}{'problems'} eq '');
			$results_map{$num_of_tasks}{'problems'} = "$names[0]: " . $results_map{$num_of_tasks}{'problems'}
				if($results_map{$num_of_tasks}{'verdict0'} eq 'unknown');
			$sum_time[0] += int($results_map{$num_of_tasks}{'time'})
				if($results_map{$num_of_tasks}{'time'} !~ /-/);
			$sum_good_time[0] += int($results_map{$num_of_tasks}{'time'})
				if(($results_map{$num_of_tasks}{'verdict0'} ne 'unknown')
				and ($results_map{$num_of_tasks}{'time'} !~ /-/));
			$sum_memory[0] += int($results_map{$num_of_tasks}{'memory'})
				if(($results_map{$num_of_tasks}{'memory'} !~ /-/)
				and ($results_map{$num_of_tasks}{'verdict0'} ne 'unknown'));
			$results_map{$num_of_tasks}{'memory'} = "$names[0]: " . $results_map{$num_of_tasks}{'memory'};
			$results_map{$num_of_tasks}{'time'} = "$names[0]: " . $results_map{$num_of_tasks}{'time'};
		}
		elsif($_ =~ /^link_to_results=(.*)/)
		{
			$links[0] = $1;
		}
		elsif($_ =~ /^name_of_runtask=(.*)/)
		{
			$full_names[0] = $1;
		}
	}
	close($first_file);
	if($num_of_tasks == 0)
	{
		#print_debug_warning "Entry file '$files[0]' hasn't results!\n";
		exit(1);
	}

	
	for(my $i = 1; $i < $num_of_files; $i++)
	{
		open(my $next_file, '<', $files[$i]) or die "Couldn't open file '$files[$i]' for read: $ERRNO!";
		while(<$next_file>)
		{
			chomp($_);
			if($_ =~ /^commit=(.*);memory=(.*);time=(.*);rule=(.*);kernel=(.*);driver=(.*);main=(.*);verdict=(.*);ideal_verdict=(.*);old_verdict=.*?;#(.*)<@>(.*)$/)
			{
				my %tmp_results_map;
				$tmp_results_map{1} = {
						'commit' => $1,
						'memory' => $2,
						'time' => $3,
						'rule' => $4,
						'kernel' => $5,
						'driver' => $6,
						'main' => $7,
						'next_verdict' => $8,
						'ideal_verdict' => $9,
						'comment' => $10,
						'problems' => $11,
						'verdict_type' => 0,
						'is_found' => 0
				};
				if($tmp_results_map{1}{'comment'} =~ /^#/)
				{
					$tmp_results_map{1}{'comment'} = $POSTMATCH;
					$tmp_results_map{1}{'verdict_type'} = 1;
				}
				$tmp_results_map{1}{'problems'} = '-'
					if($tmp_results_map{1}{'problems'} eq '');
				foreach my $key (keys %results_map)
				{
					if(($tmp_results_map{1}{'commit'} eq $results_map{$key}{'commit'})
						and ($tmp_results_map{1}{'driver'} eq $results_map{$key}{'driver'})
						and ($tmp_results_map{1}{'main'} eq $results_map{$key}{'main'})
						and ($tmp_results_map{1}{'rule'} eq $results_map{$key}{'rule'})
						and ($tmp_results_map{1}{'kernel'} eq $results_map{$key}{'kernel'}))
					{
						$tmp_results_map{1}{'is_found'} = 1;
						$results_map{$key}{"verdict$i"} = $tmp_results_map{1}{'next_verdict'};
						$results_map{$key}{'problems'} = $results_map{$key}{'problems'} . "<br>$names[$i]: " . $tmp_results_map{1}{'problems'}
							if($tmp_results_map{1}{'next_verdict'} eq 'unknown');
						$results_map{$key}{'memory'} = $results_map{$key}{'memory'} . "<br>$names[$i]: " . $tmp_results_map{1}{'memory'};
						$results_map{$key}{'time'} = $results_map{$key}{'time'} . "<br>$names[$i]: " . $tmp_results_map{1}{'time'};
						$sum_time[$i] += int($tmp_results_map{1}{'time'})
							if($tmp_results_map{1}{'time'} !~ /-/);
						$sum_good_time[$i] += int($tmp_results_map{1}{'time'})
							if(($results_map{$key}{"verdict$i"} ne 'unknown')
							and ($tmp_results_map{1}{'time'} !~ /-/));
						$sum_memory[$i] += int($tmp_results_map{1}{'memory'})
							if(($tmp_results_map{1}{'memory'} !~ /-/)
							and ($results_map{$key}{"verdict$i"} ne 'unknown'));

					}
				}
				if($tmp_results_map{1}{'is_found'} == 0)
				{
					#print_debug_debug "New task in the second file was found: commit='$tmp_results_map{1}{'commit'}'";
					$num_of_tasks++;
					$results_map{$num_of_tasks} = {
						'commit' => $tmp_results_map{1}{'commit'},
						'rule' => $tmp_results_map{1}{'rule'},
						'kernel' => $tmp_results_map{1}{'kernel'},
						'driver' => $tmp_results_map{1}{'driver'},
						'main' => $tmp_results_map{1}{'main'},
						"verdict$i" => $tmp_results_map{1}{'next_verdict'},
						'ideal_verdict' => $tmp_results_map{1}{'ideal_verdict'},
						'comment' => $tmp_results_map{1}{'comment'},
						'problems' => $tmp_results_map{1}{'problems'},
						'verdict_type' => $tmp_results_map{1}{'verdict_type'}
					};
#					$results_map{$num_of_tasks}{'memory'} = "$names[$i]: " . $tmp_results_map{1}{'memory'};
					print "ERROR: Undefined time for $results_map{$num_of_tasks}{'commit'}; file $i; \n"  unless(defined($results_map{$num_of_tasks}{'time'}));
					$sum_time[$i] += int($tmp_results_map{1}{'time'})
						if($tmp_results_map{1}{'time'} !~ /-/);
					$sum_good_time[$i] += int($tmp_results_map{1}{'time'})
						if(($tmp_results_map{1}{'verdict$i'} ne 'unknown')
						and ($tmp_results_map{1}{'time'} !~ /-/));
					$sum_memory[$i] += int($tmp_results_map{1}{'memory'})
						if(($tmp_results_map{1}{'memory'} !~ /-/)
						and ($tmp_results_map{1}{'verdict$i'} ne 'unknown'));
					$results_map{$num_of_tasks}{'memory'} = "$names[$i]: " . $tmp_results_map{1}{'memory'};
                                        $results_map{$num_of_tasks}{'time'} = "$names[$i]: " . $tmp_results_map{1}{'time'};

				}
			}
			elsif($_ =~ /^link_to_results=(.*)/)
			{
				$links[$i] = $1;
			}
			elsif($_ =~ /^name_of_runtask=(.*)/)
			{
				$full_names[$i] = $1;
			}
		}
		close($next_file);
	}
	foreach my $key (keys %results_map)
	{
		for(my $k = 0; $k < $num_of_files; $k++)
		{
			$results_map{$key}{"verdict$k"} = 'n/a'
				unless(defined($results_map{$key}{"verdict$k"}));
		}
	}
	#print_debug_trace "Starting generation of html report..";
	my $html_results;
	
	my @num_safe_safe;
	my @num_safe_unsafe;
	my @num_safe_unknown;
	my @num_unsafe_safe;
	my @num_unsafe_unsafe;
	my @num_unsafe_unknown;
	for(my $i = 0; $i < $num_of_files; $i++)
	{
		push(@num_safe_safe, 0);
		push(@num_safe_unsafe, 0);
		push(@num_safe_unknown, 0);
		push(@num_unsafe_safe, 0);
		push(@num_unsafe_unsafe, 0);
		push(@num_unsafe_unknown, 0);
	}
	my $num_of_found_bugs = 0;
	my $num_of_unknown_mains = 0;
	my $num_of_undev_rules = 0;
	my $num_of_all_bugs = 0;
	
	open($html_results, '>', $report_file) or die "Couldn't open file '$html_results' for write: $ERRNO!";
	print($html_results "<!DOCTYPE html>
<meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\">\n<html>
	<head>
		<style type=\"text\/css\">
		body {background-color:#FFEBCD}
		p {color:#2F4F4F}
		th {color:#FFA500}
		td {background:#98FB98}
		td {color:#191970}
		th {background:#3CB371}
		</style>
	</head>
<body>

<h1 align=center style=\"color:#FF4500\"><u>Commit tests multiply results</u></h1>

<p style=\"color:#483D8B\"><big>Result table:</big></p>

<table border=\"2\">\n<tr>
	<th>№</th>
	<th>Rule</th>
	<th>Kernel</th>
	<th>Commit</th>
	<th>Module</th>
	<th>Main</th>
	<th><small>Ideal verdict</small></th>\n");
	for(my $i = 0; $i < $num_of_files; $i++)
	{
		print($html_results "<th><small>$full_names[$i]</small></th>\n	");
	}
	print($html_results "<th>Memory(KB)</th>
	<th>Time(ms)</th>
	<th>Comment</th>
	<th>Problems</th>\n</tr>");
	my $cnt = 0;
	for(my $i = 1; $i <= $num_of_tasks; $i++)
	{
		if(($results_map{$i}{'main'} ne 'n/a')
			and ($results_map{$i}{'rule'} ne 'n/a'))
		{
			$cnt++;
			$num_of_all_bugs++ if($results_map{$i}{'ideal_verdict'} eq 'unsafe');
			for(my $j = 0; $j < $num_of_files; $j++)
			{
				if(($results_map{$i}{"verdict$j"} eq 'unsafe')
					and ($results_map{$i}{'verdict_type'} == 0)
					and ($results_map{$i}{'ideal_verdict'} eq 'unsafe'))
				{
					$num_of_found_bugs++;
					last;
				}
			}
			for(my $j = 0; $j < $num_of_files; $j++)
			{
				$num_safe_unsafe[$j]++ if(($results_map{$i}{'ideal_verdict'} eq 'safe')
										  and ($results_map{$i}{"verdict$j"} eq 'unsafe'));
				$num_safe_unknown[$j]++ if(($results_map{$i}{'ideal_verdict'} eq 'safe')
										  and ($results_map{$i}{"verdict$j"} eq 'unknown'));
				$num_unsafe_safe[$j]++ if(($results_map{$i}{'ideal_verdict'} eq 'unsafe')
										  and ($results_map{$i}{"verdict$j"} eq 'safe'));
				$num_safe_safe[$j]++ if(($results_map{$i}{'ideal_verdict'} eq 'safe')
										  and ($results_map{$i}{"verdict$j"} eq 'safe'));
				$num_unsafe_unsafe[$j]++ if(($results_map{$i}{'ideal_verdict'} eq 'unsafe')
										  and ($results_map{$i}{"verdict$j"} eq 'unsafe'));
				$num_unsafe_unknown[$j]++ if(($results_map{$i}{'ideal_verdict'} eq 'unsafe')
										  and ($results_map{$i}{"verdict$j"} eq 'unknown'));
			}
			print($html_results "\n<tr>
				<td>$cnt</td>
				<td>$results_map{$i}{'rule'}</td>
				<td>$results_map{$i}{'kernel'}</td>
				<td>$results_map{$i}{'commit'}</td>
				<td><small>$results_map{$i}{'driver'}</small></td>
				<td><small>$results_map{$i}{'main'}</small></td>
				<td");
			print($html_results " style=\"color:#9F79EE\"")
				if(($results_map{$i}{'verdict_type'} == 1)
					and ($results_map{$i}{'ideal_verdict'} eq 'unsafe'));
			print($html_results ">$results_map{$i}{'ideal_verdict'}</td>");
			for(my $j = 0; $j < $num_of_files; $j++)
			{
				print($html_results "<td style=\"color:#");
				if(($results_map{$i}{'ideal_verdict'} ne $results_map{$i}{"verdict$j"})
					and ($results_map{$i}{"verdict$j"} ne 'unknown'))
				{
					print($html_results "CD2626");
				}
				elsif($results_map{$i}{"verdict$j"} eq 'unknown')
				{
					print($html_results "FF00FF");
				}
				else
				{
					print($html_results "191970");
				}
				print($html_results "\">");
				print($html_results "$results_map{$i}{\"verdict$j\"}")
					if($results_map{$i}{"verdict$j"} ne 'n/a');
				print($html_results "Not found!") if($results_map{$i}{"verdict$j"} eq 'n/a');
				print($html_results "</td>\n");
			}
			
			print($html_results "<td>$results_map{$i}{'memory'}</td>
				<td>$results_map{$i}{'time'}</td>
				<td><small>$results_map{$i}{'comment'}</small></td>
				<td><small>$results_map{$i}{'problems'}</small></td>\n</tr>\n");
		}
		$num_of_unknown_mains++ if(($results_map{$i}{'main'} eq 'n/a')
										and ($results_map{$i}{'rule'} ne 'n/a'));
		$num_of_undev_rules++ if($results_map{$i}{'rule'} eq 'n/a');
	}
	print($html_results "<\/table>\n<br><br><hr>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<a href=\"$links[$j]\">Link to visualizer with your $names[$j] results.</a><br>\n");
	}
	print($html_results "<hr><p style=\"color:#483D8B\"><big>Summary</big></p>\n<table border=\"1\">\n<tr>
		<th style=\"color:#00008B;background:#66CD00\"></th>");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<th style=\"color:#00008B;background:#66CD00\"><small>$full_names[$j]</small><br>Ideal->New</th>\n");
	}	
	print($html_results "</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->unsafe:</th>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<td style=\"color:#00008B;background:#CAFF70\">$num_unsafe_unsafe[$j]</td>\n");
	}
	print($html_results "</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->safe:</th>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<td style=\"color:#00008B;background:#CAFF70\">$num_unsafe_safe[$j]</td>\n");
	}
	print($html_results "</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">unsafe->unknown:</th>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<td style=\"color:#00008B;background:#CAFF70\">$num_unsafe_unknown[$j]</td>\n");
	}
	print($html_results "</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->safe:</th>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<td style=\"color:#00008B;background:#CAFF70\">$num_safe_safe[$j]</td>\n");
	}
	print($html_results "</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->unsafe:</th>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<td style=\"color:#00008B;background:#CAFF70\">$num_safe_unsafe[$j]</td>\n");
	}
	print($html_results "</tr>\n<tr>
		<th style=\"color:#00008B;background:#66CD00\">safe->unknown:</th>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<td style=\"color:#00008B;background:#CAFF70\">$num_safe_unknown[$j]</td>\n");
	}
	print($html_results "</tr>\n</table>\n<hr>
		<p style=\"color:#483D8B\"><big>Target bugs</big></p>
		<p> Ldv-tools found $num_of_found_bugs of $num_of_all_bugs bugs;<br> Total number of bugs: $num_of_all_bugs;</p>
		<br><p> No main: $num_of_unknown_mains;<br> No rule: $num_of_undev_rules</p><br>");
	print($html_results "<table border=\"1\">\n<tr>
		<th style=\"color:#00008B;background:#66CD00\"></th>");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		print($html_results "<th style=\"color:#00008B;background:#66CD00\"><small>$full_names[$j]</small></th>\n");
	}
	print($html_results "</tr>\n<tr>\n   <td style=\"color:#00008B;background:#66CD00\">Expended time for verifying (minutes)</td>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		$sum_time[$j] = $sum_time[$j]/60000;
		print($html_results "   <td>$sum_time[$j]</td>\n");
	}
	print($html_results "</tr>\n<tr>\n   <td style=\"color:#00008B;background:#66CD00\">Expended time for verifying where result is (un)safe (minutes)</td>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		$sum_good_time[$j] = $sum_good_time[$j]/60000;
		print($html_results "   <td>$sum_good_time[$j]</td>\n");
	}
	print($html_results "</tr>\n<tr>\n   <td style=\"color:#00008B;background:#66CD00\">Average memory for each (un)safe task (KB)</td>\n");
	for(my $j = 0; $j < $num_of_files; $j++)
	{
		my $delitel = $num_unsafe_safe[$j] + $num_unsafe_unsafe[$j] + $num_safe_safe[$j] + $num_safe_unsafe[$j];
		$delitel = 1 unless($delitel);
		$sum_memory[$j] = int($sum_memory[$j]/$delitel);
		print($html_results "   <td>$sum_memory[$j]</td>\n");
	}
	print($html_results "</tr></table><hr>");
	my $cnt2 = 0;
	print($html_results "<p style=\"color:#483D8B\"><big>Modules with unknown mains:</big></p>\n<table border=\"1\">\n<tr>
		<th style=\"background:#00C5CD;color:#191970\">№</th>
		<th style=\"background:#00C5CD;color:#191970\">Rule</th>
		<th style=\"background:#00C5CD;color:#191970\">Kernel</th>
		<th style=\"background:#00C5CD;color:#191970\">Commit</th>
		<th style=\"background:#00C5CD;color:#191970\">Module</th>
		<th style=\"background:#00C5CD;color:#191970\">Ideal verdict</th>
		<th style=\"background:#00C5CD;color:#191970\">Comment</th>\n</tr>");
	for(my $i = 1; $i <= $num_of_tasks; $i++)
	{
		if(($results_map{$i}{'main'} eq 'n/a') and ($results_map{$i}{'rule'} ne 'n/a'))
		{
			$cnt2++;
			print($html_results "<tr>
			<td style=\"background:#87CEFF;color:#551A8B\">$cnt2</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'rule'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'kernel'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'commit'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'driver'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'ideal_verdict'}</td>
			<td style=\"background:#87CEFF;color:#551A8B\">$results_map{$i}{'comment'}</td>\n</tr>");
		}
	}
	print($html_results "</table>\n<br>");
	my $cnt3 = 0;
	print($html_results "<hr><p style=\"color:#483D8B\"><big>Undeveloped rules:</big></p><table border=\"1\">\n<tr>
			<th style=\"background:#CD5555;color:#363636\">№</th>
			<th style=\"background:#CD5555;color:#363636\">Kernel</th>
			<th style=\"background:#CD5555;color:#363636\">Commit</th>
			<th style=\"background:#CD5555;color:#363636\">Module</th>
			<th style=\"background:#CD5555;color:#363636\">Ideal verdict</th>
			<th style=\"background:#CD5555;color:#363636\">Comment</th>
			</tr>");
	for(my $i = 1; $i <= $num_of_tasks; $i++)
	{
		if($results_map{$i}{'rule'} eq 'n/a')
		{
			$cnt3++;
			print($html_results "<tr>
			<td style=\"background:#FFC1C1;color:#363636\">$cnt3</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'kernel'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'commit'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'driver'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'ideal_verdict'}</td>
			<td style=\"background:#FFC1C1;color:#363636\">$results_map{$i}{'comment'}</td>\n</tr>");
		}
	}
	print($html_results "\n</table>\n</body>\n</html>");
	close($html_results);
	#print_debug_normal "Report '$report_file' was successfully generated";
}
