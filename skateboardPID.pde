#include <SoftwareSerial.h>

#define OCCASIONALDEBUG

/*
   Front of board
   +100 power
   +degree


   -zGyro   +zGyro
   Motor1   Motor2


   -degree
   -100 power
 */
//+ = tip forward
//- = tip backward

// Accelerometer center point
#define ACCL_CENTER 470   // units

// Balance adjust
#define MAXBALANCE 90  // units
#define MINBALANCE -90 // units
#define D_BALANCE 0.8 // units

// PID control constants
#define PGAIN .7
#define IGAIN .01
#define DGAIN .05

#define INTEG_BUFFER_SIZE 32

// Other control constants
#define ACCL_MIX .05

#define GYROTODEG 1.3046875  // degrees per unit
#define ACCLTODEG .26614205575702629  // degrees per unit

// Turning constants
#define TURNPOT_MARGIN 7
#define STEER_MARGIN 3
#define STEER_CORRECT_POWER .15
#define STEER_POWER .15
#define MIN_STEER 90

// Digital I/O defines
#define HEARTBEAT    13

#ifdef OCCASIONALDEBUG
#define BAUD 57600
uint8_t counter;
#endif

float steer_req;
float balance_trim;
float ygyro_ref;
float zgyro_ref;
float turnpot_ref;
float level;

void setup() {
	pinMode(HEARTBEAT, OUTPUT);
#ifdef OCCASIONALDEBUG
	Serial.begin(BAUD);
#endif

	init_sensors();
	init_motors();

	// Build up some previous values
	for (uint8_t i=0; i<200; i++) {
		run_magic();
	}

	// 5 seconds may seem long but it doesn't work too well unless its 5 seconds
	//delay (5000);

	ygyro_ref = read_ygyro();
	zgyro_ref = read_zgyro();

	signal_go_time();

	// Wait for user to level board
	/*
	while (true) {
		if (abs(level) < 10)
			break;
	}
	*/

	// the turnpot's value at center is different when at rest and when stood on
	// So take the reference point after the user is on the board
	turnpot_ref = read_turnpot();

	level = 0;
	
	now_going();
}

void adj_balance() {
	balance_trim = constrain(balance_trim + (D_BALANCE * read_bal_switch()), MINBALANCE, MAXBALANCE);
}

float zgyro, steer;
void process_steering() {
	// steering here
	zgyro = -(read_zgyro() - zgyro_ref);
	steer = read_turnpot() - turnpot_ref;

	// If going straight
	if (abs(steer) <= TURNPOT_MARGIN) {
		if (abs(zgyro) > STEER_MARGIN)
			steer_req = STEER_CORRECT_POWER * zgyro;
	}
	// We are turning
	else {
		if (steer < turnpot_ref)
			steer += TURNPOT_MARGIN;
		else
			steer -= TURNPOT_MARGIN;

		// Scale according to speed
		steer_req = steer * STEER_POWER * ((-abs(level) * (1-MIN_STEER)/100) + 1);
	}
}

uint8_t filt_ind;
float filt_level[7];
float old_level;
float integ_buffer[INTEG_BUFFER_SIZE];
uint8_t ibuffer_ind = 0;
float integral = 0;

void run_magic() {
	// P
	level = PGAIN * ((1 - ACCL_MIX) * level + ACCL_MIX * (read_accl() - ACCL_CENTER));

	// I
	integral -= integ_buffer[ibuffer_ind];
	integ_buffer[ibuffer_ind] = level;
	integral += integ_buffer[ibuffer_ind];
	ibuffer_ind = (ibuffer_ind + 1) % INTEG_BUFFER_SIZE;

	level += IGAIN * integral;

	// D
	level += DGAIN * (read_ygyro() - ygyro_ref);

	// Testing the Savitsky Golay filter for motor levels as well
	for (int filt_ind=0; filt_ind<6; filt_ind++) {
		filt_level[filt_ind] = filt_level[filt_ind+1];
	}
	filt_level[6] = level;

	// Magic numbers!!!
	level = ((-2*filt_level[0]) + 
			 ( 3*filt_level[1]) + 
			 ( 6*filt_level[2]) + 
			 ( 7*filt_level[3]) + 
			 ( 6*filt_level[4]) + 
			 ( 3*filt_level[5]) + 
			 (-2*filt_level[6]))/21.0; 
}

int16_t motorL;
int16_t motorR;
void set_motors()
{
	motorL = level - steer;
	motorR = level + steer;

	motorL = constrain(motorL, -20, 20);
	motorR = constrain(motorR, -20, 20);

	send_motor_command(motorL, motorR);

#ifdef OCCASIONALDEBUG
	printStatusToSerial();
#endif
}

uint8_t pulseCounterA = 0;
uint8_t pulseCounterB = 1;
uint8_t pulseCounterDir = -1;
uint8_t cycleCount = 0;
void heartbeat()
{
	// TODO: replace with a proper PWM blinky
	if (pulseCounterA % 50 == 0)
	{
		pulseCounterB += pulseCounterDir;
		if (pulseCounterB <= 1)
			pulseCounterDir = 1;
		if (pulseCounterB >= 5)
			pulseCounterDir = -1;
		pulseCounterA = 0;
	}

	if (cycleCount % pulseCounterB == 0)
		digitalWrite(HEARTBEAT, HIGH);
	else
		digitalWrite(HEARTBEAT, LOW);

	cycleCount++;
	if (cycleCount == 100)
		cycleCount = 0;
	pulseCounterA++;
}


void loop()
{
	run_magic();
	set_motors();

#ifdef OCCASIONALDEBUG
	counter++;
	counter%=128;
#endif
}

#ifdef OCCASIONALDEBUG
void printStatusToSerial()
{
	if (counter == 127)
	{
		Serial.println("=========");
		Serial.print("lvl: ");
		Serial.println(level);
		Serial.print("mL: ");
		Serial.println(motorL);
		Serial.print("mR: ");
		Serial.println(motorR);
		Serial.print("accl: ");
		Serial.println(read_accl() - ACCL_CENTER);
		Serial.print("gyro: ");
		Serial.println(read_ygyro()-ygyro_ref);
	}
}
#endif

