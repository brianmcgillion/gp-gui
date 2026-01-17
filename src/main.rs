use iced::{
    Element, Event, Length, Size, Subscription, Task, Theme, keyboard,
    widget::operation::{focus_next, focus_previous},
    widget::{Id, Space, button, column, container, row, text, text_input},
    window,
};
use log::info;

mod config;
mod gpclient;

fn main() -> iced::Result {
    env_logger::init();

    info!("Starting GlobalProtect VPN GUI");

    // Setup signal handlers for cleanup on SIGINT/SIGTERM
    setup_signal_handlers();

    iced::application(GpGui::new, GpGui::update, GpGui::view)
        .title(GpGui::title)
        .window(window::Settings {
            size: Size::new(500.0, 450.0),
            min_size: Some(Size::new(400.0, 350.0)),
            max_size: Some(Size::new(700.0, 600.0)),
            resizable: true,
            decorations: true,
            transparent: false,
            ..Default::default()
        })
        .theme(GpGui::theme)
        .subscription(GpGui::subscription)
        .run()
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

impl GpGui {
    fn new() -> (Self, Task<Message>) {
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
            Task::none(),
        )
    }

    fn title(&self) -> String {
        match self.state {
            ConnectionState::Disconnected => String::from("GlobalProtect VPN - Disconnected"),
            ConnectionState::Connecting => String::from("GlobalProtect VPN - Connecting..."),
            ConnectionState::Connected { .. } => String::from("GlobalProtect VPN - Connected"),
        }
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::EventOccurred(event) => {
                if let Event::Keyboard(keyboard::Event::KeyPressed { key, modifiers, .. }) = event {
                    match key {
                        keyboard::Key::Named(keyboard::key::Named::Tab) => {
                            // Handle Tab key - move focus forward
                            if modifiers.shift() {
                                return focus_previous();
                            } else {
                                return focus_next();
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
                Task::none()
            }
            Message::GatewayChanged(gateway) => {
                self.gateway = gateway;
                Task::none()
            }
            Message::UsernameChanged(username) => {
                self.username = username;
                Task::none()
            }
            Message::PasswordChanged(password) => {
                self.password = password;
                Task::none()
            }
            Message::FocusNext => {
                // This is called when Enter is pressed in gateway or username field
                // Focus moves: gateway → username → password (then ConnectPressed)
                focus_next()
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

                Task::perform(
                    async move { gpclient::connect_vpn(state, config).await },
                    |result| Message::Connected(result.map_err(|e| e.to_string())),
                )
            }
            Message::DisconnectPressed => {
                info!("[UI] Disconnect button pressed");
                let state = self.vpn_state.clone();

                Task::perform(
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
                Task::none()
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
                Task::none()
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
            .center_x(Length::Fill)
            .center_y(Length::Fill)
            .into()
    }

    fn theme(&self) -> Theme {
        Theme::Dark
    }

    fn subscription(&self) -> Subscription<Message> {
        iced::event::listen().map(Message::EventOccurred)
    }

    fn view_disconnected(&self) -> Element<'_, Message> {
        let mut content = column![
            text("GlobalProtect VPN").size(28),
            Space::new().height(5),
            text("● Disconnected").size(14),
            Space::new().height(15),
            text("VPN Server").size(13),
            text_input("e.g., access.tii.ae", &self.gateway)
                .id(self.gateway_id.clone())
                .on_input(Message::GatewayChanged)
                .on_submit(Message::FocusNext)
                .padding(8)
                .size(14),
            Space::new().height(12),
            text("Username").size(13),
            text_input("Username", &self.username)
                .id(self.username_id.clone())
                .on_input(Message::UsernameChanged)
                .on_submit(Message::FocusNext)
                .padding(8)
                .size(14),
            Space::new().height(12),
            text("Password").size(13),
            text_input("Password", &self.password)
                .id(self.password_id.clone())
                .on_input(Message::PasswordChanged)
                .on_submit(Message::ConnectPressed)
                .padding(8)
                .size(14)
                .secure(true),
            Space::new().height(15),
            button(text("Authenticate & Connect").size(16))
                .on_press(Message::ConnectPressed)
                .padding(10)
                .width(Length::Fill),
        ]
        .spacing(4)
        .padding(25)
        .max_width(450);

        if let Some(error) = &self.error {
            content = content.push(Space::new().height(12));
            content = content.push(text(format!("Error: {}", error)).size(13));
        }

        content.into()
    }

    fn view_connecting(&self) -> Element<'_, Message> {
        column![
            text("GlobalProtect VPN").size(28),
            Space::new().height(20),
            text("● Connecting...").size(18),
            Space::new().height(15),
            text("Please wait while the VPN connection is established...").size(13),
        ]
        .spacing(8)
        .padding(25)
        .max_width(450)
        .into()
    }

    fn view_connected(&self, connected_at: &str) -> Element<'_, Message> {
        let connected_at = connected_at.to_string();
        column![
            text("GlobalProtect VPN").size(28),
            Space::new().height(5),
            text("● Connected").size(18),
            Space::new().height(20),
            row![
                text("Gateway:").size(13),
                Space::new().width(8),
                text(self.gateway.clone()).size(13)
            ]
            .spacing(4),
            Space::new().height(8),
            row![
                text("Username:").size(13),
                Space::new().width(8),
                text(self.username.clone()).size(13)
            ]
            .spacing(4),
            Space::new().height(8),
            row![
                text("Connected at:").size(13),
                Space::new().width(8),
                text(connected_at).size(13)
            ]
            .spacing(4),
            Space::new().height(20),
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

impl Drop for GpGui {
    fn drop(&mut self) {
        info!("GpGui dropping, cleaning up...");
        gpclient::cleanup_on_exit();
    }
}
