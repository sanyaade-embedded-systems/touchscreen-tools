using Gtk, Gdk;

extern int getLastRawCoordinates(void * display, int deviceID, out int out_x, out int out_y);
extern void resetCalibration(void * display, int deviceID);

extern int getOutputRotation(void * display, char * outputName, out int rotation, out int mirrorX, out int mirrorY);

public class Calibrator {
	
	Gtk.Window window;
	ProgressBar prgTimer;

	int tapCount = 0;
	int timerStep = 0;
	bool quit = false; 
	Label cross[4];

	int tapX[4];
	int tapY[4];

	void * display;
	int deviceID;
	string monitorName;
	SettingsWindow settWind;

	const int steps = 120;

	public Calibrator(SettingsWindow settWind, int monitor, string monitorName, void * display, int deviceID) {
		this.deviceID = deviceID;
		this.display = display;
		this.settWind = settWind;
		this.monitorName = monitorName;
		Builder builder = new Builder();
		try {
			builder.add_from_file(SHARE_DIR + "/calibration.glade");
		} catch(Error e) {
			Gtk.main_quit();
			return;
		}

		window = (Gtk.Window) builder.get_object("winCalibrate");

		prgTimer = (ProgressBar) builder.get_object("prgTimer");
		for(int i = 0; i < 4; i++) {
			cross[i] = (Label) builder.get_object("cross" + (i+1).to_string());
		}

		connect_signals();
		
		window.stick();
		window.set_keep_above(true);
		window.set_transient_for(settWind.window);

		Gdk.Screen screen = window.get_screen();
		if(monitor >= 0 && monitor < screen.get_n_monitors()) {
			Gdk.Rectangle rct;
			screen.get_monitor_geometry(monitor, out rct);
			window.move(rct.x, rct.y);
		}
		window.fullscreen();
		
		/* Reset calibration so we get "raw" values */
		resetCalibration(display, deviceID);

		window.show();
		startTimer();

	}

	void connect_signals() {
		window.map_event.connect(() => {
			Color col_black = Gdk.Color();
			var pix_data = "#define invisible_cursor_width 1\n#define invisible_cursor_height 1\n#define invisible_cursor_x_hot 0\n#define invisible_cursor_y_hot 0\nstatic unsigned short invisible_cursor_bits[] = {\n0x0000 };";
			var pix = Gdk.Pixmap.create_from_data(window.window, pix_data, 1, 1, 1, col_black, col_black);

			Gdk.GrabStatus s = Gdk.pointer_grab
(window.window, true, Gdk.EventMask.BUTTON_RELEASE_MASK, null, new Cursor.from_pixmap(pix, pix, col_black, col_black, 0, 0), 0);
			if(s != Gdk.GrabStatus.SUCCESS) {
				window.hide();
				MessageDialog md = new MessageDialog(window, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, "Unable to start calibration");
				md.secondary_text = "Exclusive access to the pointer could not be obtained.";
				md.run();
				md.destroy();
				cancel();
			}
			//stdout.printf("%i, %i %i %i %i\n", s, Gdk.GrabStatus.ALREADY_GRABBED, Gdk.GrabStatus.FROZEN, Gdk.GrabStatus.INVALID_TIME, Gdk.GrabStatus.NOT_VIEWABLE);
			return false;
		});
		window.button_release_event.connect(() => {
			tap();
			return true;
		});
	}

	bool updateClock() {
		if(quit) {
			window.dispose();
			return false;
		}

		timerStep++;
		if(timerStep <= steps) {
			prgTimer.set_fraction(1.0 - timerStep/((double) steps));
			return true;
		} else {
			cancel();
			return false;
		}
	}

	void startTimer() {
		timerStep = 0;
		Timeout.add(50,() => {
			return updateClock();
		}, Priority.DEFAULT);

		prgTimer.set_fraction(0.99);

	}
	
	public void tap() {
		int absX; int absY;
		if(getLastRawCoordinates(display, deviceID, out absX, out absY) == 1) { 
			stdout.printf("X: %i, Y: %i\n", absX, absY);

			/* Catch cases in which two taps are too near, either due to the device sending wrong
			   coordinates or the user clicking with a different input device */
			if(tapCount > 0 && ((absX - tapX[tapCount - 1]).abs() < 30 && (absY - tapY[tapCount - 1]).abs() < 30)) return;
			tapX[tapCount] = absX;
			tapY[tapCount] = absY;

			cross[tapCount].set_visible(false);

			tapCount += 1;
			timerStep = 0;
			prgTimer.set_fraction(0.99);
			if(tapCount == 4) {
				finish();
			} else {
				cross[tapCount].set_visible(true);
			}
		}		
	}

	void cancel() {
		Gdk.pointer_ungrab(0);
		/* Let helper restore original calibration */
		settWind.reloadHelper();
		window.dispose();
	}

	void finish() {
		Gdk.pointer_ungrab(0);

		applyCalibration();

//		self.window.hide();
//		MessageDialog(self.parent, gtk.DIALOG_DESTROY_WITH_PARENT, gtk.MESSAGE_INFO, gtk.BUTTONS_CLOSE, "The calibration has been performed, please test if the touchscreen is accurate now.");
//		msg.run();
//		msg.destroy();
		quit = true;
		/* Will be destroyed by timer later */
		window.hide();
	}

	void swap(ref int a, ref int b) {
		int temp = a;
		a = b;
		b = temp;
	}


	void applyCalibration() {
		settWind.autoCalibration = false;

		int minX, minY, maxX, maxY;

		//TODO apply (inverse) rotation of screen to coordinates
		if(monitorName != null) {
			int rot; int mirrX; int mirrY;
			if(getOutputRotation(display, (char *) monitorName, out rot, out mirrX, out mirrY) == 1) {
				switch(rot) {
				case 270: 
					int tmpX = tapX[0]; int tmpY = tapY[0];						
					tapX[0] = tapX[2]; tapY[0] = tapY[2];
					tapX[2] = tapX[3]; tapY[2] = tapY[3];
					tapX[3] = tapX[1]; tapY[3] = tapY[1];
					tapX[1] = tmpX; tapY[1] = tmpY;
					break;
				case 180:
					swap(ref tapX[0], ref tapX[3]); swap(ref tapY[0], ref tapY[3]);
					swap(ref tapX[1], ref tapX[2]); swap(ref tapY[1], ref tapY[2]);
					break;
				case 90:
					int tmpX = tapX[0]; int tmpY = tapY[0];
					tapX[0] = tapX[1]; tapY[0] = tapY[1];
					tapX[1] = tapX[3]; tapY[1] = tapY[3];
					tapX[3] = tapX[2]; tapY[3] = tapY[2];
					tapX[2] = tmpX; tapY[2] = tmpY;					
					break;
				}
				if(mirrX == 1) {
					swap(ref tapX[0], ref tapX[1]);
					swap(ref tapX[2], ref tapX[3]);
				}
				if(mirrY == 1) {
					swap(ref tapY[0], ref tapY[2]);
					swap(ref tapY[1], ref tapY[3]);
				}
			}
		}



/*		//TODO check if axes are inverted and correct that
		if(false) {
			swap(ref tapX[0], ref tapY[0]);
			swap(ref tapX[1], ref tapY[2]);
			swap(ref tapX[2], ref tapY[1]);
			swap(ref tapX[3], ref tapY[3]);
			//TODO set swap property
		}

		if(tapX[0] > tapX[1] && tapX[2] > tapX[3]) {
			/* Inverted horizontally /
			swap(ref tapX[0], ref tapX[1]);
			swap(ref tapX[2], ref tapX[3]);
			//TODO set swap property
		}

		if(tapY[0] > tapY[2] && tapY[1] > tapY[3]) {
			/* Inverted vertically /
			swap(ref tapY[0], ref tapY[2]);
			swap(ref tapY[1], ref tapY[3]);
			//TODO set swap property
		} */


		minX = (tapX[0] + tapX[2]) / 2;
		maxX = (tapX[1] + tapX[3]) / 2;
		minY = (tapY[0] + tapY[1]) / 2;
		maxY = (tapY[2] + tapY[3]) / 2;

		/* Calculate real min/max values from the old values that only represent the
		   positions of the crosses */
		settWind.outputMinX = minX - (maxX - minX) / 8;
		settWind.outputMaxX = maxX + (maxX - minX) / 8;
		settWind.outputMinY = minY - (maxY - minY) / 8;
		settWind.outputMaxY = maxY + (maxY - minY) / 8;

		settWind.saveDeviceSettings();
		settWind.reloadHelper();
	}

}