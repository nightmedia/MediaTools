#!perl -w
use strict;
my $config = {
  lameBinaryPath    => 'c:/windows/lame.exe',
  apeBinaryPath     => 'c:/apps/mac/mac.exe',
  flacBinaryPath    => 'c:/apps/flac/flac.exe',
  soxBinaryPath     => 'c:/apps/sox/sox.exe',
  defaultEncoding   => 'insane',
  defaultTagSource  => 'file',
  minOutputFileSize => 1000, # Files under a certain size could be the result of an encoding error
  isDebug           => 1,
};

ConvertFilesToMP3->new($config)->run(@ARGV);

package ConvertFilesToMP3;
use strict;
use warnings;
use Cwd;
use Config;
use File::Copy;
use Data::Dumper;

=pod

=head1 Description

This script can be used to convert media files found in a folder structure
to mp3 files, given a certain resolution/preset.

The script will attempt to preserve the ID3/ID3V2 tags if found,
or generate tags based on the folder structure (Artist/Album).

For efficient tagging, the script uses MP3::Info to read tags 
from the source files. If this package is not installed and tagging
is explicitly expected to be read from source files, the script will fail.

The script relies on a few external binaries, listed below.

=over

=item Lame MP3

This is the MP3 encoder, a command-line application. 
The latest version can be compiled from source, which can be retrieved here:

L<http://lame.sourceforge.net/download.php>

For Windows users, the pre-compiled binary can be downloaded from here:

L<http://www.free-codecs.com/download/lame_encoder.htm>

In order to be able to read tags from the C<.mp3> files, you need
the C<MP3::Info> package installed from CPAN.


=item MonkeyAudio encoder

I<Optional>

This command-line binary can be used to convert ape files to wav files, 
which can be then used as a source by the lame encoder to create 
the MP3 files.

The source code and the pre-compiled window application can be downloaded here:

L<http://www.monkeysaudio.com/download.html>

In order to be able to read tags from the C<.ape> files, you need
the L<http://search.cpan.org/~daniel/Audio-Musepack-0.7/lib/Audio/APE.pm Audio::APE>
package installed from CPAN. This is a pure Perl package that can be unpacked
by hand in the windows Activestate version, even if it does not show in the
active repository.


=item FLAC encoder

I<Optional>

This command-line binary can be used to convert flac files to wav files, 
which can be then used as a source by the lame encoder to create 
the MP3 files.

The source code and the pre-compiled binaries for all platforms
can be downloaded here:

L<http://flac.sourceforge.net/download.html>

In order to be able to read tags from the C<.flac> files, you need
the L<http://search.cpan.org/~daniel/Audio-FLAC-Header-2.4/Header.pm Audio::FLAC::Header>
package installed from CPAN.


=item Sound eXchange audio editor

I<Optional>

This command-line audio editor can be used in the conversion process
to apply fade-in and fade-out for each track.

The source code and the pre-compiled binaries for all platforms
can be downloaded here:

L<http://sox.sourceforge.net/>

=back


=head1 Usage

You can call this script as described below. 
If there are spaces in the folder name, you need to quote the path.

 convert.pl /my/source/folder /target/folder preset=... tags=... fade=...

If you are not providing an encoding type, the script will 
use by default "lame --preset fast standard" on all the files in the path.

=head2 Parameters

All parameters are optional.

=over

=item preset

This parameter takes the string to be used with the lame --preset option.
See the lame documentation for more information.

Examples of using acceptable values:

 preset=insane
 preset="fast extreme"

Bitrate overview (mostly based on LAME 3.98.2 results)

 Switch  Preset                  Target Kbit/s  Bitrate range kbit/s  
 -b 320  --preset insane         320            320 CBR
 -V 0    --preset fast extreme   245            220...260
 -V 1                            225            190...250
 -V 2    --preset fast standard  190            170...210
 -V 3                            175            150...195
 -V 4    --preset fast medium    165            140...185
 -V 5                            130            120...150
 -V 6                            115            100...130
 -V 7                            100            80...120
 -V 8                            85             70...105
 -V 9                            65             45...85

See L<http://wiki.hydrogenaudio.org/index.php?title=LAME> for more info.

=item process

It can have one or all of the following values:

 process=flac,wav,mp3

If not provided, all supported media files will be processed. 

If the process is in-place, the script will not process mp3 files, 
to avoid re-processing files that could have been already converted. 
You can override this behavior by providing C<mp3> in the source.

=item tags

The "tags" parameter specifies how the ID3 tags should be built.
The script will try to use the methods in order. If the ID3 was specified 
and no ID3 was defined, the other methods will be used to define the tags. 

  tags=file,path,name

The following tags can be used:

 file   Use the ID3 or FLAC tags if defined.
 
 path   Use the last two folders in the path to define the artist and the album name.
        The script will fail if the path is not deep enough to define both.
 
 name   Use the file name to separate the artist, album, and track name.
        The script will fail if the name of a track does not contain all required fields.

When using the "name" parameter, the file name would have to contain
the Artist, Album, and track title, separated by dashes:

 Artist - Album Name - Track Name.mp3

If a track contains the track number in the beginning, it will be used 
to set the track number field.

 01 - Artist - Album Name - Track Name.mp3


=item fade

When specified, this will rely on sox (http://sox.sourceforge.net/) to apply
fade-in and fade-out. You can specify these params as:

 fade=in:0.5,out:2.5,trim:0.9

This will fade in for half a second, and fade out for 2.5 seconds, then trim
the last 0.9s from the end of the file. Trim is usually required 
with longer fades because due to the nature of the fading curve 
applied to the sound, most of the second half of the fade period is silent.

The fade can be applied only to wav files.

If the source file is an mp3 file, the file will be first converted to wav,
then the fade will be applied, then the file will be converted back to mp3.

=back

B<Examples>

This will use "lame --preset cbr 160" on all the files in the path:

 convert.pl "c:/Media files/myFolder" preset="cbr 160"

You can also provide a target folder, and if it does not contain spaces,
the path can be specified without quotes:

 convert.pl "c:/Media files/myFolder" c:/Target/Folder preset="cbr 160"

If you need to fade-in/fade-out every track, you can also provide
the parameters that will be used by SOX:

 convert.pl "c:/Media files/myFolder" preset=insane fade=in:0.1,out:0.5,trim:0.2

The above command will encode in-place the source files, applying to each file
a fade-in of 0.1s, a fade-out of 0.5s and trimming the last 0.2s away 
from the end of the file.


=cut
sub new {
  my $package = shift;
  my $self    = shift;
  my $os = $^O || $Config::Config{'osname'};
  $self->{isDebug}           ||= 0;
  $self->{lameBinaryPath}    ||= 'lame';
  $self->{apeBinaryPath}     ||= '';
  $self->{flacBinaryPath}    ||= 'flac';
  $self->{soxBinaryPath}     ||= 'sox',
  $self->{defaultEncoding}   ||= 'insane';
  # How many folders deep to go look for files
  $self->{maxNestingLevel}   ||= 10;
  # Output files smaller than 10K might be the result of an encoding error.
  $self->{minOutputFileSize} ||= 10_000;
  $self->{defaultTagSource}  ||= 'file';
  $self->{defaultLameParams} ||= [
    '--quiet',
    '--add-id3v2',
  ];
  $self->{isWin32}  = $os =~ /win/ ? 1 : 0;
  return bless $self, $package;
}

sub run {
  my $self        = shift;
  my $sourcePath  = shift || $self->end("No source path provided");
  my $targetPath  = shift || '';
  my @otherParams = @_;
  $|++;
  my $defaultEncoding   = $self->{defaultEncoding};
  my $lameBinaryPath    = $self->{lameBinaryPath};
  my $minOutputFileSize = $self->{minOutputFileSize};
  my $maxNestingLevel   = $self->{maxNestingLevel};
  my $defaultLameParams = $self->{defaultLameParams};
  my $defaultTagSource  = $self->{defaultTagSource};
  my $isDebug           = $self->{isDebug};
  
  if ($targetPath =~ /=/) {
    # We don't have a second path, the next argument is a param=value
    unshift @otherParams, $targetPath;
    $targetPath = $sourcePath;
  }
  my $logPath = $self->{logPath} = $targetPath.'/activity.log';
  unlink $logPath if -e $logPath;
  
  my %params = map {
    $_ =~ /(\w+)=(.+)/ ? (lc $1, $2) : ()
  } @otherParams;
  
  my (@messages, @tagsSource, @errors);
  my $opParams        = $self->{opParams} = {};
  my @outParams       = @$defaultLameParams;
  my @processFileType = qw(ape flac wav mp3 );
  my @canTagSource    = qw(file name path );
  
  $sourcePath = $self->makeAbsolutePath($sourcePath);
  $targetPath = $self->makeAbsolutePath($targetPath);
  $self->end("Invalid path provided: $sourcePath")
   if ! -e $sourcePath
   || ! -d $sourcePath;
  
  if (! -e $targetPath) {
    mkdir($targetPath, 0777)
      || $self->end("Could not create path($targetPath): ".$!);
  }
  my $preset          = $params{preset}  || '';
  my $tagsSource      = $params{tags}    || '';
  my $fadeParams      = $params{fade}    || '';
  my $processFileType = $params{process} || '';
  
  if ($preset) {
    push @outParams, '--preset '.$preset;
  }
  else {
    push @messages, qq~No encoding standard was specified, using "$defaultEncoding"~;
    push @outParams, '--preset '.$defaultEncoding;
  }
  
  if ($processFileType) {
    my %canProcessFileType = map {$_ => 1} @processFileType;
    $processFileType =~ s/\s+//g;
    @processFileType = 
      grep { $canProcessFileType{$_} }
      split /,/, lc $processFileType;
  }
  else {
    @processFileType = grep {$_ ne 'mp3'} @processFileType
      if $sourcePath eq $targetPath;
  }
  $self->{processFileType} = { map {$_ => 1} @processFileType };
  push @messages, "The following file types will be processed: "
    .(join ',', @processFileType);
  
  my %canTagSource = map {$_ => 1} @canTagSource;
  if ($tagsSource) {
    $tagsSource =~ s/\s+//g;
    @tagsSource = split /,/, lc $tagsSource;
  }
  else {
    @tagsSource = ref $defaultTagSource
      ? @$defaultTagSource
      : ($defaultTagSource);
  }
  @tagsSource = grep { $canTagSource{$_} } @tagsSource;
  push @messages, @tagsSource
    ? "The tags will be built from: "
      .(join ', then ', @tagsSource)
    : "No ID3V2 tags will be set";
  
  if ($fadeParams) {
    # fade=in:0.5,out:2.5
    $fadeParams =~ s/\s+//g;
    my @fadeParams = split /,/, $fadeParams;
    my %fadeParams = map {
      $_ =~ /(in|out|trim):(\d+|\d*\.\d+)/i
        ? (lc $1, $2)
        : ()
    } @fadeParams;
    $self->{fadeParams} = \%fadeParams if %fadeParams;
  }
  
  push @messages, $sourcePath eq $targetPath
    ? 'The new files will be created in the same folder as the source'
    : 'The new files will be created in: '.$targetPath;
  
  my $lameParams = join ' ', @outParams;
  my $fadeMessage = $self->{fadeParams}
    ? "Fade params were specified, and can only applied to wav files.
If the source files are mp3, the fade params will be ignored.\n"
    : '';
  print ''.("=" x 60)."\n- "
    .(join "\n- ", @messages)
    .qq~\n\nThe files in the following path:\n\n\t$sourcePath\n
will be converted using the following lame params:

\t$lameBinaryPath $lameParams

$fadeMessage
You have 5 seconds to stop this...\n~;
  sleep 5;
  
  $opParams->{-LAME_PARAMS} = $lameParams;
  $opParams->{-ID3V2_TAGS}  = \@tagsSource;
  
  $self->workDir($sourcePath, $targetPath);
  $self->printMessages();
  return;
}

sub makeAbsolutePath {
  my $self = shift;
  my $path = shift;
  # If we are processing files in the current path,
  # we should make it an absolute path for lame.
  # We will also convert windows-style paths to Perl-style paths.
  if ($path eq '.') {
    $path = getcwd();
  }
  elsif ($path !~ /^(\w\:|\/)/) {
    $path = getcwd().'/'.$path;
  }
  $path =~ s/\\/\//g;
  $path =~ s/\/$//;
  return $path;
}

sub addError {
  my $self     = shift;
  my $message  = shift;
  my $messages = $self->{opParams}{-ERRORS} ||= [];
  push @$messages, $message;
  return;
}

sub addMessage {
  my $self     = shift;
  my $message  = shift;
  my $messages = $self->{opParams}{-MESSAGES} ||= [];
  push @$messages, $message;
  return;
}

sub printMessages {
  my $self     = shift;
  my $logPath  = $self->{logPath};
  my $messages = $self->{opParams}{-MESSAGES} ||= [];
  my $errors   = $self->{opParams}{-ERRORS}   ||= [];
  my $hasLog;
  if (@$errors) {
    $self->toLog(("=" x 60)."\n"
      ."ERRORS found:\n".(join "\n", @$errors)."\n");
    print "Errors were found\n";
    $hasLog++;
  }
  if (@$messages) {
    $self->toLog(("=" x 60)."\n"
      ."PROCESS RESULTS:\n".(join "\n", @$messages)."\n");
    $hasLog++;
  }
  else {
    print "OK\n";
  }
  print "An activity log was created: $logPath\n"
    if $hasLog;
  return;
}

sub workDir {
  my $self        = shift;
  my $currentPath = shift;
  my $targetPath  = shift;
  my $level       = shift || 1;
  
  my $apeBinaryPath     = $self->{apeBinaryPath};
  my $flacBinaryPath    = $self->{flacBinaryPath};
  my $soxBinaryPath     = $self->{soxBinaryPath};
  my $maxNestingLevel   = $self->{maxNestingLevel};
  my $minOutputFileSize = $self->{minOutputFileSize};
  my $fadeParams        = $self->{fadeParams};
  my $processFileType   = $self->{processFileType};
  if ($fadeParams) {
    $self->end("No soxBinaryPath defined")
      if ! $soxBinaryPath;
    $self->end("The soxBinaryPath is not valid: $soxBinaryPath")
      if ! -e $soxBinaryPath;
  }
  return if $maxNestingLevel < $level;
  if (! -e $targetPath) {
    mkdir($targetPath, 0777)
      || $self->end("Could not create path($targetPath):".$!);
  }
  my $isProcessInPlace = $currentPath eq $targetPath ? 1 : 0;
  
  my ($dh, @errors, @messages);
  my $opParams   = $self->{opParams};
  my $tagsSource = $opParams->{-ID3V2_TAGS};
  my $lameParams = $opParams->{-LAME_PARAMS};
  
  if (! opendir ($dh, $currentPath)) {
    $self->addError($currentPath);
    $self->addError("Can't open $currentPath:. ".$!);
    return;
  }
  my @files = sort grep(!/^\.\.?$/, readdir($dh));
  closedir ($dh);
  $self->toLog("PATH: $currentPath");
  
  foreach my $fileName(@files) {
    my $targetFile;
    my $sourceFile = "$currentPath/$fileName";
    if (-d $sourceFile) {
      my $newTargetPath = "$targetPath/$fileName";
      if (! -e $newTargetPath) {
        mkdir($newTargetPath, 0777)
          || $self->end("Could not create path($newTargetPath):".$!);
      }
      $self->workDir($sourceFile, $newTargetPath, $level + 1); 
      next;
    };
    next if $fileName !~ /(.+)\.(\w+)$/;
    my $fRoot = $1;
    my $fExt  = lc $2;
    my $fileTags;
    if (! $processFileType->{$fExt}) {
      $self->toLog("SKIP: $fileName");
      next;
    }
    
    if ($fExt eq 'mp3') {
      $targetFile = $isProcessInPlace
        ? "$currentPath/temp.mp3"
        : "$targetPath/$fileName";
      
      unlink $targetFile
        if $isProcessInPlace && -e $targetFile;
      
      $self->toLog("CONVERT: $fileName");
      
      my $message = $self->encodeFile($sourceFile, $targetFile, $lameParams, $tagsSource);
      if ($message) {
        push @messages, $fileName;
        push @messages, @$message;
      }
      if (! -e $targetFile) {
        push @errors, $fileName;
        push @errors, "Encode failed, mp3 target file could not be created";
      }
      elsif (-s $targetFile < $minOutputFileSize) {
        push @errors, $fileName;
        push @errors, "Encode failed, output smaller than "
          .(sprintf "%.2d", $minOutputFileSize / 1000)
          ."KB, keeping original file.";
        unlink $targetFile;
        copy($sourceFile, $targetFile) if ! $isProcessInPlace;
      }
      else {
        if ($isProcessInPlace) {
          unlink $sourceFile;
          rename ($targetFile, $sourceFile)
            || $self->end("could not rename $targetFile to $sourceFile");
        }
      }
    }
    else {
      my $targetFileWav;
      if ($fExt eq 'ape') {
        if (! $apeBinaryPath) {
          $self->toLog("SKIP(No converter): $fileName");
          next;
        }
        $self->toLog("CONVERT: $fileName to wav");
        $fileTags = $self->getTagsFromFile($sourceFile, \@messages) || {};

        my $newFileName = "$fRoot.wav";
        $targetFileWav = "$currentPath/$newFileName";
        unlink $targetFileWav
          if $isProcessInPlace && -e $targetFileWav;
        
        my $cmd = qq~$apeBinaryPath "$sourceFile" "$targetFileWav" -d~;
        utf8::downgrade($cmd);
        push @messages, $cmd;
        `$cmd`;
        
        my $oldFile = $sourceFile;
        $sourceFile = $targetFileWav;
        unlink $oldFile
          if $isProcessInPlace && -e $sourceFile && $self->{deleteSourceFiles};
        $self->toLog("FAILED TO CONVERT: $fileName to $newFileName")
          if ! -e $sourceFile;
      }
      elsif ($fExt eq 'flac') {
        $self->toLog("CONVERT: $fileName to wav");
        $fileTags = $self->getTagsFromFile($sourceFile, \@messages) || {};

        my $newFileName = "$fRoot.wav";
        $targetFileWav = "$currentPath/$newFileName";
        unlink $targetFileWav
          if $isProcessInPlace && -e $targetFileWav;
        
        my $cmd = qq~$flacBinaryPath -d "$sourceFile" -o "$targetFileWav"~;
        utf8::downgrade($cmd);
        push @messages, $cmd;
        `$cmd`;
        
        my $oldFile = $sourceFile;
        $sourceFile = $targetFileWav;
        unlink $oldFile
          if $isProcessInPlace && -e $sourceFile && $self->{deleteSourceFiles};
        $self->toLog("FAILED TO CONVERT: $fileName to $newFileName")
          if ! -e $sourceFile;
      }
      
      my $tempTargetFile;
      if (-e $sourceFile && $fadeParams) {
        my $trim    = $fadeParams->{trim} || '';
        my $fadeIn  = $fadeParams->{in}   || 0;
        my $fadeOut = $fadeParams->{out}  || 0;
        if ($trim || $fadeIn || $fadeOut) {
          $tempTargetFile = "$targetPath/$fRoot.fade.wav";
          my $thisFadeParams;
          $thisFadeParams   .= " fade $fadeIn 0 $fadeOut"
            if $fadeIn || $fadeOut;
          $thisFadeParams   .= " trim =0 -$trim" if $trim;
          
          $self->toLog("FADE: $thisFadeParams");
          
          my $cmd = qq~$soxBinaryPath "$sourceFile" "$tempTargetFile" $thisFadeParams~;
          utf8::downgrade($cmd);
          push @messages, $cmd;
          `$cmd`;
          
          if (! -e $tempTargetFile) {
            $self->toLog("FAILED TO FADE: $sourceFile to $tempTargetFile")
          }
          else {
            $sourceFile = $tempTargetFile;
          }
        }
      }
      my $message;
      if (-e $sourceFile) {
        $targetFile = "$targetPath/$fRoot.mp3";
        unlink $targetFile
          if $isProcessInPlace && -e $targetFile;
        
        $message = $self->encodeFile($sourceFile, $targetFile, $lameParams, $tagsSource, $fileTags);
      }
      
      unlink $targetFileWav  if $targetFileWav;
      unlink $tempTargetFile if $tempTargetFile;
      
      if ($message) {
        push @messages, $fileName;
        push @messages, @$message;
      }
      if (! -e $targetFile) {
        push @errors, $fileName;
        push @errors, "\tEncode failed, see log";
      }
    }
  }
  if (@errors) {
    $self->addError($currentPath);
    map { $self->addError($_) } @errors;
  }
  if (@messages) {
    $self->addMessage($currentPath);
    map { $self->addMessage($_) } @messages;
  }
  return;
}

sub end {
  my $self    = shift;
  my $message = shift;
  print "$message\n";
  exit 1;
}

sub getTagsFromFile {
  my $self       = shift;
  my $sourceFile = shift;
  my $messages   = shift;
  if ($sourceFile =~ /\.flac$/i) {
    eval 'use Audio::FLAC::Header;';
    if ($@) {
      push @$messages, '=I= Could not load Audio::FLAC::Header: '.$@;
      return {};
    }
    my %tags;
    my $flac = Audio::FLAC::Header->new($sourceFile);
    my $info = $flac->tags();
    $tags{TITLE}    = $info->{TITLE}       || $info->{title}       || '';
    $tags{YEAR}     = $info->{DATE}        || $info->{date}        || '';
    $tags{ARTIST}   = $info->{ARTIST}      || $info->{artist}      || '';
    $tags{ALBUM}    = $info->{ALBUM}       || $info->{album}       || '';
    $tags{GENRE}    = $info->{GENRE}       || $info->{genre}       || '';
    $tags{TRACKNUM} = $info->{TRACKNUMBER} || $info->{tracknumber} || '';
    $tags{COMMENT}  = $info->{COMMENT}     || $info->{comment}     || '';
    # http://perldoc.perl.org/utf8.html
    foreach my $key(keys %tags) {
      utf8::decode($tags{$key});
    }
    return \%tags;
  }
  if ($sourceFile =~ /\.ape$/i) {
    eval 'use Audio::APE;';
    if ($@) {
      push @$messages, '=I= Could not load Audio::APE: '.$@;
      return {};
    }
    my %tags;
    my $mac = Audio::APE->new($sourceFile);
    my $info = $mac->tags();
    print Dumper(\%$info);

    $tags{TITLE}    = $info->{TITLE}    || $info->{title}    || '';
    $tags{YEAR}     = $info->{YEAR}     || $info->{year}     || '';
    $tags{ARTIST}   = $info->{ARTIST}   || $info->{artist}   || '';
    $tags{ALBUM}    = $info->{ALBUM}    || $info->{album}    || '';
    $tags{GENRE}    = $info->{GENRE}    || $info->{genre}    || '';
    $tags{TRACKNUM} = $info->{TRACKNUM} || $info->{track}    || '';
    $tags{COMMENT}  = $info->{COMMENT}  || $info->{comment}  || '';
    # Did not find a source file with valid unicode tags to test if this is necessary
#    foreach my $key(keys %tags) {
#      utf8::decode($tags{$key});
#    }
    return \%tags;
  }
  if ($sourceFile !~ /\.mp3$/i) {
    push @$messages, '=I= Source not an MP3 file, cannot read ID3 tags';
    return {};
  }
  eval 'use MP3::Info;';
  if ($@) {
    push @$messages, '=I= Could not load MP3::Info: '.$@;
    return {};
  }
  # This method is exported by MP3::Info
  my $tagFromFile = get_mp3tag($sourceFile) || {};
  if (! keys %$tagFromFile) {
    push @$messages, '=I= MP3 file with no ID3 tags';
  }
  else {
    push @$messages, '=I= MP3 file has ID3 tags';
  }
  return $tagFromFile;
}

sub getTagsFromPath {
  my $self       = shift;
  my $sourceFile = shift;
  my $messages   = shift;
  my %tagFromPath;
  if ($sourceFile =~ /([^\/]+)\/([^\/]+)\/(\d+)\s*-\s*([^\/]+)\.w+$/o) {
    push @$messages, '=P= Simple file name, extracting Artist/Album from path.';
    $tagFromPath{ARTIST}   = $1;
    $tagFromPath{ALBUM}    = $2;
    $tagFromPath{TRACKNUM} = $3;
    $tagFromPath{TITLE}    = $4;
  }
  elsif ($sourceFile =~ /(?:Various Artists|V\.A\.?)\/([^\/]+)\/(\d+)\s*(\.|-)\s*([^\/]+)\.w+$/oi) {
    $tagFromPath{ALBUM}    = $1;
    $tagFromPath{TRACKNUM} = $2;
    my $title              = $3;
    $tagFromPath{ARTIST}   = 'Various Artists';
    $tagFromPath{TITLE}    = $title;
    if ($title =~ /([^.]+)\s+\.\s+(.+)/o ||
        $title =~ /([^\-]+)\s+-\s+(.+)/o) {
      $tagFromPath{ARTIST} = $1;
      $tagFromPath{TITLE}  = $2;
      push @$messages, '=P= Extract artist name from file name';
    }
    else {
      push @$messages, '=P= No artist name could be determined from path or file name';
    }
  }
  return \%tagFromPath;
}

sub getTagsFromName {
  my $self       = shift;
  my $sourceFile = shift;
  my $messages   = shift;
  return if $sourceFile !~ /([^\/\\]+)\.\w+$/oi;
  my %tagFromName;
  
  my $fileName = $1;
  if ($fileName =~ /^\(([^(]*)\)(.+)/o ||
      $fileName =~ /^\[([^\]]*)\](.+)/) {
    $tagFromName{ALBUM} = $1;
    $fileName           = $2;
    push @$messages, "=N= Album name: $1";
  }
  if ($fileName =~ /(.+)\((\d\d\d\d)\)$/o) {
    $tagFromName{YEAR} = $2;
    $fileName          = $1;
    push @$messages, "=N= Album year: $2";
  }
  # 01 - Artist - Album Name - Track Name.mp3
  # 01_-_Artist_-_Album_Name_-_Track_Name.mp3
  my @fileName = map {
    $_ =~ s/_/ /g;
    $_ =~ s/\s+/ /g;
    $_ =~ s/^\s+//;
    $_ =~ s/\s+$//;
    $_
  } split /-/, $fileName;
  
  shift @fileName until $fileName[0] ne '' || ! @fileName;
  return \%tagFromName if ! @fileName;
  
  push @$messages, "=N= Using for tagging:\n\t".(join "|", @fileName);
  
  if ($fileName[0] =~ /^\d+$/) {
    $tagFromName{TRACKNUM} = shift @fileName;
  }
  if (2 < @fileName) {
    if (! exists $tagFromName{ALBUM}) {
      $tagFromName{ALBUM}  = shift @fileName;
    }
    $tagFromName{ARTIST} = shift @fileName;
    $tagFromName{TITLE}  = join '-', @fileName;
  }
  elsif (@fileName == 2) {
    $tagFromName{ARTIST} = shift @fileName;
    $tagFromName{TITLE}  = shift @fileName;
  }
  else {
    $tagFromName{TITLE}  = shift @fileName;
  }
  return \%tagFromName;
}


sub encodeFile {
  my $self           = shift;
  my $sourceFile     = shift;
  my $targetFile     = shift;
  my $lameParams     = shift;
  my $tagsSource     = shift;
  my $fileTags       = shift || {};
  my $lameBinaryPath = $self->{lameBinaryPath};
  
  my (%tag, @messages);
  # These are the params as defined by the MP3::Info
  my @mp3Params  = qw(TITLE YEAR ARTIST ALBUM GENRE TRACKNUM COMMENT);
  my %defaultTag = map { $_ => '' } @mp3Params;
  my %tagsSource = map { $_ => 1 } @$tagsSource;
  
  my $tagFromFile = %$fileTags
    ? $fileTags
    : $tagsSource{id3}
      ? $self->getTagsFromFile($sourceFile, \@messages)  || {}
      : {};
  
  my $tagFromPath = $tagsSource{path}
    ? $self->getTagsFromPath($sourceFile, \@messages) || {}
    : {};
  my $tagFromName = $tagsSource{name}
    ? $self->getTagsFromName($sourceFile, \@messages) || {}
    : {};
  
  foreach my $x(@mp3Params) {
    foreach my $tagSource(@$tagsSource) {
      # Once defined, a tag cannot be overriden
      next if exists $tag{$x} && defined $tag{$x} && $tag{$x} ne '';
      
      if ($tagSource eq 'path') {
        $tag{$x} = $tagFromPath->{$x} if exists $tagFromPath->{$x} && defined $tagFromPath->{$x};
      }
      elsif ($tagSource eq 'file') {
        $tag{$x} = $tagFromFile->{$x} if exists $tagFromFile->{$x} && defined $tagFromFile->{$x};
      }
      elsif ($tagSource eq 'name') {
        $tag{$x} = $tagFromName->{$x} if exists $tagFromName->{$x} && defined $tagFromName->{$x};
      }
      $tag{$x} = $defaultTag{$x} if ! exists $tag{$x} || ! defined $tag{$x} || $tag{$x} eq '';
      $tag{$x} =~ s/^\((.*)\)$/ $1 /; # Remove round braces
      $tag{$x} =~ s/^\[(.*)\]$/ $1 /; # and square braces
      $tag{$x} =~ s/\s+/ /g;          # Replace multiple space-type chars with one space
      $tag{$x} =~ s/^\s+//;           # Strip leading spaces
      $tag{$x} =~ s/\s+$//;           # and trailing spaces
      $tag{$x} =~ s/[|\\\/]/~/g;      # use "~" instead of one of the following: | / \
      $tag{$x} =~ s/"/'/g;            # use ' instead of "
      push @messages, "=== $x($tagSource)=$tag{$x}" if $tag{$x} ne '';
    }
  }
  $tag{'TRACKNUM'} = $1
    if defined $tag{'TRACKNUM'} && $tag{'TRACKNUM'} =~ /(\d+)\D/;
  
  my %tagFlag = (
    TITLE    => 'tt',
    YEAR     => 'ty',
    ARTIST   => 'ta',
    ALBUM    => 'tl',
    GENRE    => 'tg',
    TRACKNUM => 'tn',
    COMMENT  => 'tc',
  );
  
  $lameParams .= join '',
    map {sprintf ' --%s "%s"', $tagFlag{$_}, $tag{$_}}
    grep {defined $tag{$_} && $tag{$_} ne ''}
    sort keys %tagFlag;
  
  if ($self->{isWin32}) {
    $sourceFile =~ s/\//\\/g;
    $targetFile =~ s/\//\\/g;
  }
  my $sourceSize = -s $sourceFile;
  if (! $sourceSize) {
    push @messages, "ERROR:Invalid source file, cannot read size";
  }
  else {
    my $cmd = qq~$lameBinaryPath $lameParams "$sourceFile" "$targetFile"~;
    # See:
    # http://search.cpan.org/~jhi/perl-5.8.1/pod/perlunicode.pod
    # http://perldoc.perl.org/utf8.html
    utf8::downgrade($cmd);
    push @messages, $cmd;
    `$cmd`;
    if (! -e $targetFile) {
      push @messages, "ERROR:Could not convert(no target file)";
    }
    else {
      my $targetSize = -s $targetFile;
      if ($targetSize) {
        push @messages, "Size changed from "
          .(sprintf '%.2d', $sourceSize / 1000)."K to "
          .(sprintf '%.2d', $targetSize / 1000)."K.";
      }
      else {
        push @messages, "ERROR:Could not convert: can not get target file size";
        unlink $targetFile;
      }
    }
  }
  push @messages, ("=" x 40);
  
  @messages = () if ! $self->{isDebug};
  
  return \@messages;
}

sub toLog {
  my $self    = shift;
  my $message = shift;
  my $logPath = $self->{logPath};
  open(my $fh, '>>', $logPath) || die $!;
  print $fh "$message\n";
  close($fh);
}