function [] = melody_extractor(filename,extraction_type,remove_index,...
                               instrFreqLow,instrFreqHigh,...
                               startSec,duration,debug)
%%%
% Usage:
% filename
%    should be readable by audioread
% extraction_type 
%     Defines what to extract. Set remove_index if this is set to be 'remove'
%     can be: remove | add_all_octaves | add_all_lower_octaves |
%             add_only_one_note | add_neighbor_octaves | add_voice_range
% remove_index
%     should be populated if the extraction_type is 'remove'
% instrFreqLow, instrFreqHigh
%     Frequency range the melody lies in
%     instrument frequency range can be obtained from here:
%         http://www.zytrax.com/tech/audio/audio.html
%     suggestions:
%       MIDI:
%         instrFreqLow = 1000;
%         instrFreqHigh = 10000;
%       Trombone:
%         instrFreqLow = 50;
%         instrFreqHigh = 600;
% startSec
%     location to start reading the audio file
% duration
%     duration to read the audio file
% debug
%     set true in order to plot various details
%                   
%%%

[raw,fs] = audioread(filename);

if nargin < 4
    instrFreqLow = 0;
    instrFreqHigh = 50000;
end

if nargin < 6 || startSec==-1
    raw_short = raw(:,1);
else
    raw_short = raw(startSec*fs+1:(startSec+duration)*fs+1,1);
end
    
if nargin < 8
    debug = false;
end

% hyper parameters
shiftAmount = 25*10^-3;
overlap = 0.1;
cents = 50;

L = floor(fs*shiftAmount/overlap); % hamming window size
L = L-mod(L,2);

if debug
    fig_num = 0;

    fig_num = fig_num+1;
    figure(fig_num)
    plot(linspace(0,5,length(raw_short)),raw_short)
end
%sound(raw_short,fs)

% create the hamming window
window = hamming(L,'periodic');

if debug
    fig_num = fig_num+1;
    figure(fig_num)
    plot(window)
    title('hamming window')
end

% prepare note frequencies
currFreq = 27.5;
noteFreq = [];
while currFreq<fs/2
    noteFreq(length(noteFreq)+1) = currFreq;
    currFreq = currFreq*2^(1/12);
end
upperBoundaries = noteFreq*2^(cents/1200);
lowerBoundaries = noteFreq*2^(-cents/1200);

freqMap = linspace(0,fs/2,L/2)';
freqMapLog = log10(freqMap);

votableVoterFirst = min(find(noteFreq>instrFreqLow));
votableVoterLast = max(find(noteFreq<instrFreqHigh));
lowerSing = min(find(noteFreq>110));
upperSing = max(find(noteFreq<1200));

new_signal = zeros(size(raw_short));
count = 0;
voteHistory = [];
prevMaxNoteInd = 1;
voteMax = 0;
for frameNum=1:L*overlap:length(raw_short)-L
    frameNumInt = floor(frameNum);
    count = count+1;
    % apply the window
    cutFrame = raw_short(frameNumInt+1:frameNumInt+L);
    if unique(cutFrame)==0
        continue
    end
    windowed = cutFrame.*window;
    if count==10 && debug
        fig_num = fig_num+1;
        figure(fig_num)
        clf
        hold on
        plot(cutFrame)
        plot(windowed)
        title('Example windowing before/after')
    end

    % FFT the output
    ffted = fft(windowed);
    if count==10 && debug
        fig_num = fig_num+1;
        figure(fig_num)
        plot(linspace(0,fs/2,length(ffted)/2),abs(ffted(1:length(ffted)/2)))
        title('FFT Magnitude')
        xlim([0 5000])
        xlabel('Frequency (Hz)')
    end

    % start voting
    num_voters = length(noteFreq);
    ffted_half = ffted(1:end/2);
    ffted_mag = abs(ffted_half);
    ffted_rms = ffted_mag/sqrt(2);
    ffted_spl = 20*log10(ffted_mag/sqrt(2)*10^12);
    
    %weightedVotingPower = ffted_mag.*toMel;
    ffted_A = [ffted_spl.^2 ffted_spl freqMapLog.^2 freqMapLog ones(size(freqMapLog))];
    coeff = [0.004396639; 0.597783934; -18.5425192; 117.2167996; -178.2674593];
    phon = ffted_A*coeff;
    weightedVotingPower = (10.^((phon-40)*0.030103));

    if count==10 && debug
        fig_num = fig_num+1;
        figure(fig_num)
        plot(linspace(0,fs/2,length(ffted)/2),weightedVotingPower)
        title('After Sone Conversion')
        xlim([0 5000])
        xlabel('Frequency (Hz)')
    end
    
    % vote
    votes = zeros(num_voters,1);
    for i=votableVoterFirst:votableVoterLast
        freqBit = freqMap>lowerBoundaries(i) & freqMap<upperBoundaries(i);
        votes(i) = sum(freqBit.*weightedVotingPower);
    end
    if count==10 && debug
        fig_num = fig_num+1;
        figure(fig_num)
        plot(noteFreq,votes)
        title('Note Votes')
        xlim([0 5000])
        xlabel('Frequency (Hz)')
    end

    % total the votes according to note name
    vote_total = zeros(12,1);
    for i=1:12
        vote_total(i) = sum(votes(i:12:end));
    end
    if count==10 && debug
        fig_num = fig_num+1;
        figure(fig_num)
        plot(vote_total)
        title('Note Name Votes')
        str = {'A','Bb','B','C','C#','D','Eb','E','F','F#','G','Ab'};
        set(gca, 'XTickLabel',str, 'XTick',[1:12]);
    end

    % figure out which frequencies survive
    if strcmp(extraction_type,'remove')
        vote_total_sort = sort(vote_total,'descend');
        surviving_notes = ones(length(freqMap),1);
        for i=1:length(remove_index)
            index = find(vote_total==vote_total_sort(i));
            ind = remove_index(index);
            for j=ind:12:num_voters
                killed = freqMap>lowerBoundaries(j) & freqMap<upperBoundaries(i);
                surviving_notes = surviving_notes - killed;
            end
        end
    else
        [val,maxNoteInd] = max(votes);
        if val<voteMax/20
            maxNoteInd = prevMaxNoteInd;
        else
            voteMax = max(voteMax,val);
        end
        
        if length(voteHistory)<10
            voteHistory = [voteHistory,maxNoteInd];
            ind = mod(maxNoteInd,12);
        else
            voteHistory = [maxNoteInd voteHistory(1,end-1)];
            ind = mod(mode(voteHistory),12);
        end
        if ind==0
            ind = 12;
        end

        if strcmp(extraction_type,'add_all_octaves')
            % include all octaves
            surviving_notes = ind:12:num_voters;
            
        elseif strcmp(extraction_type,'add_all_lower_octaves')
            % include all lower octives
            surviving_notes = ind:12:maxNoteInd;
        
        elseif strcmp(extraction_type,'add_only_one_note')
            % only include that note
            surviving_notes = maxNoteInd;
        
        elseif strcmp(extraction_type,'add_neighbor_octaves')
            % include that note and one octave up/down
            surviving_notes = maxNoteInd;
            if maxNoteInd>12
                surviving_notes = [surviving_notes maxNoteInd-12];
            end
            if maxNoteInd+12<=length(lowerBoundaries)
                surviving_notes = [surviving_notes maxNoteInd+12];
            end
            
        elseif strcmp(extraction_type,'add_voice_range')
            % include octaves of the note that is between A1-A5 Hz
            surviving_notes = (lowerSing-mod(lowerSing,12))+ind:12:upperSing;
            
        end
        % convert the surviving notes to surviving frequencies
        % also, shape the frequencies so it doesn't sound so harsh
        surviving_freqs = zeros(length(freqMap),1);
        for loc=1:length(surviving_notes)
            ind = surviving_notes(loc);
            survived = freqMap>lowerBoundaries(ind) ...
                        & freqMap<upperBoundaries(ind);
            oneLoc = find(survived);
            width = max(oneLoc) - min(oneLoc) + 1;
            shape_window = hamming(width,'periodic');
            %shape_window = shape_window(floor(width/2):floor(width/2)+width-1);
            surviving_freqs(min(oneLoc):max(oneLoc)) = shape_window;
        end
    end
    
    surviving_ffted = surviving_freqs.*ffted_half;
    if mod(length(ffted),2)==0
        surviving_ffted = [surviving_ffted; fliplr(surviving_ffted)];
    else
        surviving_ffted = [surviving_ffted; 0; fliplr(surviving_ffted)];
    end
    if debug && count==10
        freqz = linspace(0,fs/2,length(ffted)/2);
        fig_num = fig_num+1;
        figure(fig_num)
        clf
        hold on
        plot(freqz,weightedVotingPower)
        plot(freqz,surviving_freqs.*abs(weightedVotingPower))
        title('Surviving Notes Frequency')
        xlabel('Frequency (Hz)')
        xlim([0 5000])
        legend('FFT Magnitude','Extracted Frequencies for Output');
    end
    
    new_signal(frameNumInt+1:frameNumInt+L) ...
        = new_signal(frameNumInt+1:frameNumInt+L)+real(ifft(surviving_ffted));
    
    prevMaxNoteInd = maxNoteInd;
end

if debug
    fig_num = fig_num+1;
    figure(fig_num)
    plot(new_signal)
end

% normalize the output
new_signal = new_signal/max(new_signal);

audiowrite(strcat('output.m4a'),new_signal,fs)
end