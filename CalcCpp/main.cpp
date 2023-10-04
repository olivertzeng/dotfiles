/**
 * @author      : olivertzeng (olivertzeng@$HOSTNAME) 
 * @file        : 04/10/2023
 * @created     : main 
 */

#include <iostream>
using namespace std;
int main() {
	int A,B,N,ians;
	cout << "Please input the dividend, divisor, and the accuracy, seperated with spaces: ";
	cin >> A >> B >> N;
	ians = A / B;
	A -= ians;
	int ans[N];
	if (A != 0) {
		string Bs = to_string(B);
		B /= 10^-(Bs.size());
		for (int i=0;i<N;i++) {
			for (int j=1;j<=9;j++) {
				switch() {

				}
			}
		}
	}
	else {
		cout << ians;
	}
    return 0;
}


