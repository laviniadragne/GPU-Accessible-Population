Nume: Dragne Lavinia-Stefana
Grupa: 334 CA

		ARHITECTURA SISTEMELOR DE CALCUL
		Tema #3 - GPU Accessible Population


	Continutul proiectului este urmatorul:
	
	- fisierele helper.cu, main.cu, helper.h

	- Makefile
	
	- acest fisier README

	* Organizare si implementare - Cum s-a implementat solutia?

        In fisierul main.cu se afla entry-point-ul programului. 
    Se preiau argumentele din linia de comanda, pentru fiecare
    test, cele 3 argumente si se apeleaza functia sampleFileIO,
    care contine logica de calculare a distantei dintre orase
    si de scriere a populatiei in fisierul de iesire.

        In functia sampleFileIO aloc datele pentru CPU (host) ce va
    coordona executia si pentru GPU (device) unitatea care va executa
    calculele. Am folosit particula host / device in denumirea 
    variabilelor pentru a indica rolul pe care il are fiecare.
        Se verifica ca alocarea datelor a fost realizata cu succes.
        Datele privind latitudinea/ longitudinea si populatia le-am
    retinut in vectori de tip unsigned long long int pentru a putea 
    folosi (mai tarziu) functia de atomicAdd, pentru adunari atomice
    pe populatie.
        Datele sunt citite in variabile host si copiate in variabile
    device.
        Pentru calculul functiilor sin si cos anterior distantei am
    folosit 4 vectori.

        Pornesc N thread-uri, repartizate in N / 256 blocuri, apeland
    kernelul calcSinCos. Fiecare thread CUDA va calcula sinusul si 
    cosinusul pentru latitudine/ longitudine. Cosinusul l-am calculat ca
    fiind sqrt (1 - sin ^2), pentru a reduce din timpul de executie. 
    Datele le stochez in vectorii sin_angle, cos_angle, sin_angle_90, 
    cos_angle_90. Fiecare thread se va ocupa de prelucrarea datelor 
    pentru elementele din vectori de la pozitia corespunzatoare id-ului 
    lui.
        Pentru a bloca toate operatiile pe CPU, pana cand se executa
    toate cele de pe GPU am folosit cudaDeviceSynchronize.
        Pentru verificarea de eventuale erori am folosit
    cudaGetLastError.

        Lansez un kernel, compareDist, ce va fi rulat in paralel de N
    thread-uri, repartizate in N / 256 blocuri.
        Fiecare thread se va ocupa de a calcula distanta de la un anumit
    oras (cel aflat la indexul thread-ului) la toate celelalte. Se va 
    itera prin toate orasele ramase (N - index orase) si se calculeaza
    distanta de la orasul curent la ele, folosind valorile sin si cos
    stocate in vectorii primiti ca parametru. Logica de calcul a 
    distantei dintre 2 orase este luata din functia geoDistance din 
    schelet.
        Daca distanta este mai mica decat kmRange, se aduna populatiile
    orasului curent la cel prin care iterez si invers. Am folosit
    functia atomicAdd, pentru ca adunarea sa fie atomica, altfel 
    existand posibilitatea ca populatia orasului curent sa fie 
    actualizata in acelasi timp de un alt thread si rezultatul final
    sa nu fie cel corect.
        Pentru accesul la vectori, pentru a imbunatati timpul de 
    rulare, am folosit aritmetica cu pointeri si keyword-ul register.
        Am copiat datele din vectorul de device in cel de host si
    ulterior le-am scris in fisier.
        Se elibereaza resursele folosite.

    Output performante obtinute

        Am rulat de mai multe ori, in zile diferite, la ore diferite, 
    folosind scriptul ./run_fep_checker.sh. Am observat ca la diferite
    rulari, timpul prezenta o inconsistenta, probabil in functie de
    incarcarea cozilor. Am obtinut uneori si diferente de 30s pe 
    aceeasi placa, pe aceeasi implementare, in zile diferite, dar am 
    considerat ca degradarea solutiei se datoareaza mediului de 
    testare (vazand ca exista si pe forumul temei aceeasi problema
    la colegii mei). Timpul de rulare l-am masurat folosind CUDA 
    events. Prezint mai jos o lista a timpilor, pe cele 3
    placi si mentionez ca acestia sunt timpii medii de rulare (am obtinut
    in 1% din cazuri timpi care difereau si cu 30s). (Am masurat 
    timpul de rulare al for-ului din main.cu, ce contine practic
    intreaga logica a implementarii).

    * pe toate cele 5 teste:
    GPU="A100"
    4.712s(cel mai bun timp masurat)

    
    GPU="P100"
    12.338s(cel mai bun timp masurat)
    12.604s
    13.126s


    GPU="K40M"
    ~47s (cel mai bun timp masurat)
    53.495s
    55.236s

    Deci, se poate observa ca la majoritatea rularilor solutia mea se 
    incadreaza in timpul din checker pe placile A100 (cel mai des pe 
    aceasta) sau P100 (la limita). Ca si perfomanta solutia mea
    obtine cei mai buni timpi pe A100, urmata de P100 si mai apoi de K40M
    si obtine punctaj maxim de 90/90 pe A100 (cel mai des) si la limita
    pe P100.
    Tin sa precizez (asa cum am vazut pe forum) ca rularea pentru 
    verificare temei sa se faca pe placa A100.

    * doar pe primele 4 teste (fara H1):
    GPU="K40M"
    4.448s

    Nu am reusit sa rulez primele 4 teste decat pe K40M, pentru ca
    doar pe aceasta mi-o dadea checker-ul in ziua in care am testat
    doar cele 4 teste.

    Deci, pentru doar primele 4 teste timpul se incadreaza in limita din
    checker, tinand cont ca pe K40M aveam cel mai mare timp pe cele 5 
    teste, acum este chiar de 10 ori mai mic (4.448s vs 47s). Testul
    al 5-lea este intr-adevar de aproximativ 9 ori mai mare ca si
    dimensiune a datelor de input fata de al 4-lea. Astfel doar primele
    4 teste se incadreaza in limita de timp pe toate placile,
    obtinand un punctaj de 70/90.

    Mentionez ca pentru a se testa doar cele 4 teste trebuie sa se 
    decomenteze for-ul din main.cu cu (argc - 3) si sa se comenteze
    for-ul actual.

    In prima implementare pe care o facusem am pornit de la un timp
    initial de aproximativ 200s pe K40M, calculand cu for in for
    toate distantele de la un oras la altul. Deci consider ca am redus
    timpul considerabil fata de prima varianta. De asemenea, inainte
    sa implementez cu CUDA, am realizat o implementare in cpp, care
    era corecta ca si output, dar pentru ca foloseam doar CPU-ul, aveam
    un timp de aprox 120s doar pe primul test. Astfel, am observat
    puterea de calcul a GPU-ului comparativa cu cea a CPU-ului.
    Mentionez ca am incercat mai multe valori pentru blockSize, dar
    am observat ca 256 este cea optima.


    Bibliografie
    1. Laboratoarele 7,8,9 ASC - OCW
    2. Folosirea variabilei register pentru optimizare: 
    https://curs.upb.ro/2021/mod/forum/discuss.php?d=15073
    https://ocw.cs.pub.ro/courses/asc/laboratoare/05
    3. Scheletul oferit de echipa de ASC pentru implementarea temei
    (+ Makefile-ul din schelet)
    







    
