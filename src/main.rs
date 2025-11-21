use iced::{
    Application, Command, Element, Event, Length, Settings, Subscription, Theme, keyboard,
    widget::{Space, button, column, container, row, text, text_input, text_input::Id},
};
use log::info;

mod config;
mod gpclient;

fn main() -> iced::Result {
    env_logger::init();

    if !gpclient::check_running_as_root() {
        eprintln!("Error: This application must be run as root");
        eprintln!("Run with: sudo ./gp-gui");
        std::process::exit(1);
    }

    info!("Starting GlobalProtect VPN GUI (Iced POC)");

    // Setup signal handlers for cleanup on SIGINT/SIGTERM
    setup_signal_handlers();

    GpGui::run(Settings {
        window: iced::window::Settings {
            size: iced::Size::new(500.0, 450.0),
            resizable: false,
            ..Default::default()
        },
        ..Default::default()
    })
}

fn setup_signal_handlers() {
    use std::sync::atomic::{AtomicBool, Ordering};

    static CLEANUP_DONE: AtomicBool = AtomicBool::new(false);

    let cleanup = || {
        if !CLEANUP_DONE.swap(true, Ordering::SeqCst) {
            info!("Signal received, cleaning up...");
            gpclient::cleanup_on_exit();
        }
    };

    ctrlc::set_handler(move || {
        cleanup();
        std::process::exit(0);
    })
    .expect("Error setting Ctrl-C handler");
}

#[derive(Debug, Clone)]
enum Message {
    GatewayChanged(String),
    UsernameChanged(String),
    PasswordChanged(String),
    ConnectPressed,
    DisconnectPressed,
    Connected(Result<String, String>),
    Disconnected(Result<String, String>),
    EventOccurred(Event),
    FocusNext,
}

struct GpGui {
    state: ConnectionState,
    gateway: String,
    username: String,
    password: String,
    error: Option<String>,
    vpn_state: gpclient::VpnState,
    gateway_id: Id,
    username_id: Id,
    password_id: Id,
}

#[derive(Debug, Clone, PartialEq)]
enum ConnectionState {
    Disconnected,
    Connecting,
    Connected { connected_at: String },
}

impl Application for GpGui {
    type Message = Message;
    type Executor = iced::executor::Default;
    type Flags = ();
    type Theme = Theme;

    fn new(_flags: ()) -> (Self, Command<Message>) {
        let config = config::load_config();

        (
            Self {
                state: ConnectionState::Disconnected,
                gateway: config
                    .as_ref()
                    .map(|c| c.vpn_server.clone())
                    .unwrap_or_else(|| "access.tii.ae".to_string()),
                username: config
                    .as_ref()
                    .map(|c| c.username.clone())
                    .unwrap_or_default(),
                password: String::new(),
                error: None,
                vpn_state: gpclient::create_vpn_state(),
                gateway_id: Id::new("gateway"),
                username_id: Id::new("username"),
                password_id: Id::new("password"),
            },
            Command::none(),
        )
    }

    fn title(&self) -> String {
        match self.state {
            ConnectionState::Disconnected => String::from("GlobalProtect VPN - Disconnected"),
            ConnectionState::Connecting => String::from("GlobalProtect VPN - Connecting..."),
            ConnectionState::Connected { .. } => String::from("GlobalProtect VPN - Connected"),
        }
    }

    fn update(&mut self, message: Message) -> Command<Message> {
        match message {
            Message::EventOccurred(event) => {
                if let Event::Keyboard(keyboard::Event::KeyPressed { key, modifiers, .. }) = event {
                    match key {
                        keyboard::Key::Named(keyboard::key::Named::Tab) => {
                            // Handle Tab key - move focus forward
                            if modifiers.shift() {
                                return iced::widget::focus_previous();
                            } else {
                                return iced::widget::focus_next();
                            }
                        }
                        keyboard::Key::Named(keyboard::key::Named::Enter) => {
                            // Handle Enter key based on current state
                            match &self.state {
                                ConnectionState::Disconnected => {
                                    return self.update(Message::ConnectPressed);
                                }
                                ConnectionState::Connected { .. } => {
                                    return self.update(Message::DisconnectPressed);
                                }
                                ConnectionState::Connecting => {
                                    // Ignore Enter while connecting
                                }
                            }
                        }
                        _ => {}
                    }
                }
                Command::none()
            }
            Message::GatewayChanged(gateway) => {
                self.gateway = gateway;
                Command::none()
            }
            Message::UsernameChanged(username) => {
                self.username = username;
                Command::none()
            }
            Message::PasswordChanged(password) => {
                self.password = password;
                Command::none()
            }
            Message::FocusNext => {
                // This is called when Enter is pressed in gateway or username field
                // Focus moves: gateway → username → password (then ConnectPressed)
                iced::widget::focus_next()
            }
            Message::ConnectPressed => {
                info!("[UI] Connect button pressed");
                self.state = ConnectionState::Connecting;
                self.error = None;

                let config = gpclient::VpnConfig {
                    gateway: self.gateway.clone(),
                    username: self.username.clone(),
                    password: self.password.clone(),
                    ..Default::default()
                };

                let state = self.vpn_state.clone();

                Command::perform(
                    async move { gpclient::connect_vpn(state, config).await },
                    |result| Message::Connected(result.map_err(|e| e.to_string())),
                )
            }
            Message::DisconnectPressed => {
                info!("[UI] Disconnect button pressed");
                let state = self.vpn_state.clone();

                Command::perform(
                    async move { gpclient::disconnect_vpn(state).await },
                    |result| Message::Disconnected(result.map_err(|e| e.to_string())),
                )
            }
            Message::Connected(result) => {
                match result {
                    Ok(msg) => {
                        info!("[UI] Connection successful: {}", msg);
                        self.state = ConnectionState::Connected {
                            connected_at: chrono::Local::now()
                                .format("%Y-%m-%d %H:%M:%S")
                                .to_string(),
                        };
                        self.password.clear();
                        self.error = None;
                    }
                    Err(e) => {
                        info!("[UI] Connection failed: {}", e);
                        self.state = ConnectionState::Disconnected;
                        self.error = Some(e);
                    }
                }
                Command::none()
            }
            Message::Disconnected(result) => {
                match result {
                    Ok(msg) => {
                        info!("[UI] Disconnection successful: {}", msg);
                        self.error = None;
                    }
                    Err(e) => {
                        info!("[UI] Disconnection failed: {}", e);
                        self.error = Some(e);
                    }
                }
                self.state = ConnectionState::Disconnected;
                Command::none()
            }
        }
    }

    fn view(&self) -> Element<'_, Message> {
        let content = match &self.state {
            ConnectionState::Disconnected => self.view_disconnected(),
            ConnectionState::Connecting => self.view_connecting(),
            ConnectionState::Connected { connected_at } => self.view_connected(connected_at),
        };

        container(content)
            .width(Length::Fill)
            .height(Length::Fill)
            .center_x()
            .center_y()
            .into()
    }

    fn theme(&self) -> Theme {
        Theme::Dark
    }

    fn subscription(&self) -> Subscription<Message> {
        iced::event::listen().map(Message::EventOccurred)
    }
}

impl Drop for GpGui {
    fn drop(&mut self) {
        info!("GpGui dropping, cleaning up...");
        gpclient::cleanup_on_exit();
    }
}

impl GpGui {
    fn view_disconnected(&self) -> Element<'_, Message> {
        let mut content = column![
            text("GlobalProtect VPN").size(28),
            Space::with_height(5),
            text("● Disconnected").size(14),
            Space::with_height(15),
            text("VPN Server").size(13),
            text_input("e.g., access.tii.ae", &self.gateway)
                .id(self.gateway_id.clone())
                .on_input(Message::GatewayChanged)
                .on_submit(Message::FocusNext)
                .padding(8)
                .size(14),
            Space::with_height(12),
            text("Username").size(13),
            text_input("Username", &self.username)
                .id(self.username_id.clone())
                .on_input(Message::UsernameChanged)
                .on_submit(Message::FocusNext)
                .padding(8)
                .size(14),
            Space::with_height(12),
            text("Password").size(13),
            text_input("Password", &self.password)
                .id(self.password_id.clone())
                .on_input(Message::PasswordChanged)
                .on_submit(Message::ConnectPressed)
                .padding(8)
                .size(14)
                .secure(true),
            Space::with_height(15),
            button(text("Authenticate & Connect").size(16))
                .on_press(Message::ConnectPressed)
                .padding(10)
                .width(Length::Fill),
        ]
        .spacing(4)
        .padding(25)
        .max_width(450);

        if let Some(error) = &self.error {
            content = content.push(Space::with_height(12));
            content = content.push(text(format!("Error: {}", error)).size(13));
        }

        content.into()
    }

    fn view_connecting(&self) -> Element<'_, Message> {
        column![
            text("GlobalProtect VPN").size(28),
            Space::with_height(20),
            text("● Connecting...").size(18),
            Space::with_height(15),
            text("Please wait while the VPN connection is established...").size(13),
        ]
        .spacing(8)
        .padding(25)
        .max_width(450)
        .into()
    }

    fn view_connected(&self, connected_at: &str) -> Element<'_, Message> {
        column![
            text("GlobalProtect VPN").size(28),
            Space::with_height(5),
            text("● Connected").size(18),
            Space::with_height(20),
            row![
                text("Gateway:").size(13),
                Space::with_width(8),
                text(&self.gateway).size(13)
            ]
            .spacing(4),
            Space::with_height(8),
            row![
                text("Username:").size(13),
                Space::with_width(8),
                text(&self.username).size(13)
            ]
            .spacing(4),
            Space::with_height(8),
            row![
                text("Connected at:").size(13),
                Space::with_width(8),
                text(connected_at).size(13)
            ]
            .spacing(4),
            Space::with_height(20),
            button(text("Disconnect").size(16))
                .on_press(Message::DisconnectPressed)
                .padding(10)
                .width(Length::Fill),
        ]
        .spacing(4)
        .padding(25)
        .max_width(450)
        .into()
    }
}
