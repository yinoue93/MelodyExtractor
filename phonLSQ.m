intensity = csvread('loudness.csv',1,2);
freqLog = csvread('loudness.csv',1,1,[1,1,25,1]);
phons = [0,10,20,40,60,80,100];

counter = 0;
A = zeros(size(intensity,1)*size(intensity,2),5);
b = zeros(size(intensity,1)*size(intensity,2),1);
for i=1:size(intensity,2)
    p = phons(i);
    for j=1:size(intensity,1)
        counter = counter+1;
        A(counter,1) = intensity(j,i)^2;
        A(counter,2) = intensity(j,i);
        A(counter,3) = freqLog(j)^2;
        A(counter,4) = freqLog(j);
        A(counter,5) = 1;
        b(counter) = p;
    end
end

coeff = pinv(A)*b

%A*coeff