use crate::components::{MessageContext, MessageSeverity, Messages};
use crate::github::*;
use leptos::prelude::*;
use leptos::task::*;
use leptos_meta::*;
use leptos_router::components::*;
use leptos_router::hooks::{use_navigate, use_query};
use leptos_router::params::Params;
use leptos_router::*;
use server_fn::error::NoCustomError;
use std::sync::Arc;
use web_sys::MouseEvent;

const GITHUB_CLIENT_ID: &str = "Ov23lixO0S9pamhwo1u7";

#[server(ExchangeToken, "/api")]
#[worker::send]
pub async fn exchange_token(code: String) -> Result<String, ServerFnError> {
    use axum::Extension;
    use leptos_axum::extract;
    use worker::Env;

    let Extension(env): Extension<Arc<Env>> = extract().await?;
    let client_secret = env.secret("GITHUB_CLIENT_SECRET")?.to_string();

    let client = reqwest::Client::new();
    let response = client
        .post("https://github.com/login/oauth/access_token")
        .header("Accept", "application/json")
        .form(&[
            ("client_id", GITHUB_CLIENT_ID),
            ("client_secret", &client_secret),
            ("code", &code),
        ])
        .send()
        .await?;

    if response.status().is_success() {
        let token_response = response.json::<TokenResponse>().await?;
        Ok(token_response.access_token)
    } else {
        let error = response.json::<ErrorResponse>().await?;
        Err(ServerFnError::ServerError::<NoCustomError>(error.error))
    }
}

#[derive(Clone, Copy)]
pub struct UserContext {
    logged_in: RwSignal<bool>,
    token: RwSignal<Option<String>>,
    user: LocalResource<Option<User>>,
}

impl UserContext {
    pub fn new() -> Self {
        let logged_in = RwSignal::new(false);
        let token = RwSignal::new(None);

        let user = LocalResource::new(move || async move {
            match token.get() {
                Some(token) => UserAccessToken::from_string(token).user().await.ok(),
                None => None,
            }
        });

        Effect::new(move |_| {
            if let Some(access_token) = get_token_from_storage() {
                token.set(Some(access_token));
                logged_in.set(true);
            }
        });

        Self { logged_in, token, user }
    }

    pub fn login(&self, token: String) {
        set_token_storage(&token);
        self.token.set(Some(token));
        self.logged_in.set(true);
    }

    pub fn logout(&self) {
        remove_token_storage();
        self.token.set(None);
        self.logged_in.set(false);
    }

    pub fn get_token(&self) -> Option<String> {
        self.token.get()
    }

    pub fn is_logged_in(&self) -> bool {
        self.logged_in.get()
    }

    pub fn user(&self) -> LocalResource<Option<User>> {
        self.user
    }
}

fn set_token_storage(token: &str) {
    if let Some(storage) = window().local_storage().ok().flatten() {
        let _ = storage.set_item("github_token", token);
    }
}

fn remove_token_storage() {
    if let Some(storage) = window().local_storage().ok().flatten() {
        let _ = storage.remove_item("github_token");
    }
}

fn get_token_from_storage() -> Option<String> {
    window()
        .local_storage()
        .ok()
        .flatten()
        .and_then(|storage| storage.get_item("github_token").ok().flatten())
}

#[component]
fn LoginButton() -> impl IntoView {
    let auth_url = format!(
        "https://github.com/login/oauth/authorize?client_id={}&redirect_uri=http://127.0.0.1:8787/oauth/callback&scope=read:project+read:org",
        GITHUB_CLIENT_ID
    );

    view! {
        <a
            href=auth_url
            class="inline-block px-4 py-2 bg-gray-900 text-white rounded hover:bg-gray-700 transition-colors"
        >
            "Login with GitHub"
        </a>
    }
}

#[component]
fn RepositoryList() -> impl IntoView {
    let repos = LocalResource::new(move || async move {
        match get_access_token_from_storage() {
            Some(token) => token.user_repositories().await.ok().unwrap_or_default(),
            None => vec![],
        }
    });

    view! {
        <div class="space-y-4">
            <h2 class="text-2xl font-bold">"Your Repositories"</h2>
            <div class="space-y-2">
                <Suspense fallback=move || view! { <p>"Loading..."</p> }.into_any()>
                    {move || Suspend::new(async move {
                        repos.await.into_iter().map(|repo| {
                            view! {
                            <div class="p-4 border rounded hover:bg-gray-50">
                                <a href=repo.html_url.clone() target="_blank" class="font-medium hover:underline">
                                    {repo.full_name.clone()}
                                </a>
                                    <span class="ml-2 text-sm text-gray-500">
                                        {if repo.private { "Private" } else { "Public" }}
                                    </span>
                                </div>
                            }
                        }).collect_view()
                    })}
                </Suspense>
            </div>
        </div>
    }
}

#[component]
fn OrganizationList() -> impl IntoView {
    let user_ctx = expect_context::<UserContext>();

    let org_data = LocalResource::new(move || async move {
        match (get_access_token_from_storage(), user_ctx.user().await) {
            (Some(token), Some(user)) => {
                let orgs = token.organizations(&user.login).await.ok().unwrap_or_default();
                let mut org_map = std::collections::HashMap::new();
                for org in orgs {
                    if let Ok(repositories) = token.org_repositories(&org.login).await {
                        org_map.insert(org, repositories);
                    }
                }
                org_map
            }
            _ => Default::default(),
        }
    });

    view! {
        <div class="space-y-4">
            <h2 class="text-2xl font-bold">"Your Organizations"</h2>
            <div class="space-y-6">
                <Suspense fallback=move || view! { <p>"Loading..."</p> }>
                    <div>
                    { move || Suspend::new(async move {
                        org_data.await.into_iter().map(|(org, repositories)| {
                            view! {
                                <div class="space-y-2">
                                    <div class="flex items-center space-x-2">
                                        <img src=org.avatar_url.clone() class="w-8 h-8 rounded-full" />
                                        <h3 class="text-xl font-semibold">{org.login.clone()}</h3>
                                    </div>
                                    <div class="ml-10 space-y-2">
                                        {repositories.into_iter().map(|repo| {
                                            view! {
                                                <div class="p-4 border rounded hover:bg-gray-50">
                                                    <a href=repo.html_url.clone() target="_blank" class="font-medium hover:underline">
                                                        {repo.full_name.clone()}
                                                    </a>
                                                    <span class="ml-2 text-sm text-gray-500">
                                                        {if repo.private { "Private" } else { "Public" }}
                                                    </span>
                                                </div>
                                            }
                                        }).collect_view()}
                                    </div>
                                </div>
                            }
                        }).collect_view()
                    })}
                    </div>
                </Suspense>
            </div>
        </div>
    }
}

#[component]
fn UserDropdown(#[prop(into)] user_name: String, #[prop(into)] avatar_url: String) -> impl IntoView {
    let (is_open, set_is_open) = signal(false);
    let user_ctx = expect_context::<UserContext>();

    let toggle_dropdown = move |e: MouseEvent| {
        e.stop_propagation();
        set_is_open.update(|value| *value = !*value);
    };

    // Close dropdown when clicking outside
    let close_dropdown = move |_| set_is_open.set(false);
    window_event_listener(leptos::ev::click, close_dropdown);

    view! {
        <div class="relative">
            <img
                src=avatar_url
                class="w-8 h-8 rounded-full cursor-pointer"
                alt="User avatar"
                on:click=toggle_dropdown
            />
            <Show when=move || is_open.get()>
                <div class="absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg py-1 z-10">
                    <div class="px-4 py-2 text-sm text-gray-700 border-b">
                        {user_name.clone()}
                    </div>
                    <a
                        href="/settings"
                        class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                        on:click=move |_| set_is_open.set(false)
                    >
                        "Settings"
                    </a>
                    <button
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
                        on:click=move |_| {
                            user_ctx.logout();
                            use_navigate()("/", NavigateOptions::default());
                        }
                    >
                        "Log out"
                    </button>
                </div>
            </Show>
        </div>
    }
}

#[component]
fn MenuBar() -> impl IntoView {
    let user_ctx = expect_context::<UserContext>();

    view! {
        <div class="bg-sky-700 text-white p-4 flex items-center justify-between">
            <div class="flex items-center space-x-4">
                <h1 class="text-2xl font-bold">"Proof of Tests"</h1>
                <div class="bg-sky-600 px-3 py-1 rounded-full text-sm">
                    "0 tests" // We'll make this dynamic later
                </div>
            </div>
            <div>
                {move || {
                    if user_ctx.is_logged_in() {
                        let user_resource = user_ctx.user();
                        view! {
                            {move || user_resource.get().as_deref().map(|user| match user {
                                Some(user) => view! {
                                    <UserDropdown
                                        user_name=user.login.clone()
                                        avatar_url=user.avatar_url.clone()
                                    />
                                }.into_any(),
                                None => view! { <div>"Loading..."</div> }.into_any(),
                            })}
                        }.into_any()
                    } else {
                        view! { <LoginButton /> }.into_any()
                    }
                }}
            </div>
        </div>
    }
}

pub fn shell(options: LeptosOptions) -> impl IntoView {
    view! {
        <!DOCTYPE html>
        <html lang="en">
            <head>
                <meta charset="utf-8"/>
                <meta name="viewport" content="width=device-width, initial-scale=1"/>

                <AutoReload options=options.clone() />
                <HydrationScripts options/>
                <MetaTags/>
            </head>
            <body class="bg-sky-100">
                <App/>
            </body>
        </html>
    }
}

#[component]
pub fn App() -> impl IntoView {
    provide_meta_context();

    let message_ctx = MessageContext::new();
    provide_context(message_ctx);

    let user_ctx = UserContext::new();
    provide_context(user_ctx);

    view! {
        <Stylesheet href="/style.css" />
        <Link rel="icon" type_="image/x-icon" href="/favicon.ico" />


        <Messages/>

        <MenuBar/>

        <div class="bg-white" style:box-shadow="0 0px 5px rgba(0, 0, 0, 0.4)">
            <div class="max-w-4xl mx-auto p-4">
                <Router>
                    <main>
                        <Routes fallback=|| "Not found">
                            <Route
                                path=path!("/")
                                view=move || {
                                    view! {
                                        <div class="space-y-8">
                                            <RepositoryList/>
                                            <OrganizationList/>
                                        </div>
                                    }
                                }
                            />
                            <Route
                                path=path!("/settings")
                                view=move || {
                                    view! { <Settings/> }
                                }
                            />
                            <Route
                                path=path!("/oauth/callback")
                                view=move || {
                                    view! {
                                        <OAuthCallback/>
                                    }
                                }
                            />
                        </Routes>
                    </main>
                </Router>
            </div>
        </div>
    }
}

#[derive(Params, Clone, Debug, PartialEq, Eq)]
struct OAuthCallbackParams {
    code: Option<String>,
}

#[component]
fn OAuthCallback() -> impl IntoView {
    let navigate = use_navigate();
    let params = use_query::<OAuthCallbackParams>();
    let message_ctx = expect_context::<MessageContext>();
    let user_ctx = expect_context::<UserContext>();

    Effect::new(move |_| {
        let navigate = navigate.clone();
        let message_ctx = message_ctx.clone();
        let user_ctx = user_ctx.clone();

        if let Ok(OAuthCallbackParams { code: Some(code) }) = params.get() {
            spawn_local(async move {
                match exchange_token(code).await {
                    Ok(token) => {
                        user_ctx.login(token);
                        message_ctx.add("Successfully logged in!", MessageSeverity::Info);
                        navigate("/", NavigateOptions::default());
                    }
                    Err(e) => {
                        message_ctx.add(format!("Failed to login: {}", e), MessageSeverity::Error);
                        navigate("/", NavigateOptions::default());
                    }
                }
            });
        }
    });

    view! {
        <div class="text-center">
            "Processing login..."
        </div>
    }
}

fn get_access_token_from_storage() -> Option<UserAccessToken> {
    use_context::<UserContext>()
        .and_then(|ctx| ctx.get_token())
        .map(UserAccessToken::from_string)
}

#[component]
fn Settings() -> impl IntoView {
    view! {
        <div class="space-y-4">
            <h2 class="text-2xl font-bold">"Settings"</h2>
            <p class="text-gray-600">"Settings page coming soon..."</p>
        </div>
    }
}
